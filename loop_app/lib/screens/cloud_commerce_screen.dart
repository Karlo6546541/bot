import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../services/live_backend.dart';
import '../services/commerce_backend.dart';
import '../services/stripe_backend.dart';
import '../widgets/live_media/live_media.dart';
import 'login_screen.dart';

/// Explicit online route. Legacy local orders and bids are never written here.
class CloudCommerceScreen extends StatefulWidget {
  const CloudCommerceScreen({super.key});
  @override
  State<CloudCommerceScreen> createState() => _CloudCommerceState();
}
class _CloudCommerceState extends State<CloudCommerceScreen> {
  SupabaseClient get db => Supabase.instance.client;
  LiveBackend get live => LiveBackend(db);
  CommerceBackend get commerce => CommerceBackend(db);
  String? get uid => db.auth.currentUser?.id;
  String? roomId;
  int tab = 0;
  bool busy = false, loading = true, failed = false;
  bool refreshing = false;
  List<Map<String, dynamic>> rooms = [], messages = [], lots = [], products = [], orders = [];
  Map<String, dynamic>? connection;
  Timer? timer;
  StreamSubscription<AuthState>? auth;
  RealtimeChannel? channel;
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    auth = db.auth.onAuthStateChange.listen((_) {
      connection = null;
      _refresh();
      if (roomId != null) _video();
    });
    _refresh();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }
  @override
  void dispose() {
    timer?.cancel(); auth?.cancel(); input.dispose();
    final c = channel; if (c != null) db.removeChannel(c);
    super.dispose();
  }
  Future<void> _refresh() async {
    if (refreshing || !mounted) return;
    refreshing = true;
    final selectedRoom = roomId;
    try {
      final rs = await db.from('live_rooms').select().order('created_at', ascending: false).limit(50);
      List<Map<String, dynamic>> ms = [], ls = [], ps = [], os = [];
      if (selectedRoom != null) {
        ms = await live.messages(selectedRoom);
        ls = await db.from('live_lots').select().eq('room_id', selectedRoom).order('id');
      } else if (tab == 1) {
        ps = await db.from('commerce_products').select().eq('active', true).order('created_at', ascending: false).limit(50);
      } else if (tab == 2 && uid != null) {
        os = await commerce.orders();
      }
      if (!mounted || selectedRoom != roomId) return;
      setState(() {rooms=rs;messages=ms;lots=ls;products=ps;orders=os;failed=false;loading=false;});
    } catch (_) {
      if (mounted) setState(() {failed=true;loading=false;});
    } finally {refreshing=false;}
  }
  Future<bool> _login() async {
    if (uid != null) return true;
    await LoginScreen.open(context);
    if (mounted) await _refresh();
    return mounted && uid != null;
  }
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy=true);
    try { await action(); await _refresh(); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Radnja nije uspjela. Osvježi stanje pa pokušaj ponovno.'))); }
    finally {if(mounted) setState(() => busy=false);}
  }
  Future<String?> _ask(String title, {String hint = ''}) async {
    final field=TextEditingController();
    final value=await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: TextField(controller: field, autofocus: true,
        decoration: InputDecoration(hintText: hint)),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context),child: const Text('Odustani')),
        FilledButton(onPressed: ()=>Navigator.pop(context,field.text.trim()),child: const Text('Potvrdi'))],
    ));
    // Keep the controller alive through dialog dismissal animation.
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    return value == null || value.isEmpty ? null : value;
  }
  Future<void> _open(String id) async {
    final old=channel;if(old!=null) await db.removeChannel(old);
    if (!mounted) return;
    setState(() {roomId=id;connection=null;messages=[];lots=[];});
    channel=live.watch(id, _refresh);
    await _refresh(); await _video();
  }
  Future<void> _video() async {
    final selected=roomId;if(selected==null)return;
    try {
      final value=await live.videoToken(selected);
      if(mounted && selected==roomId) setState(()=>connection=value);
    } catch (_) { /* Room may be scheduled or the host has not connected. */ }
  }
  Future<void> _leave() async {
    final old=channel;channel=null;if(old!=null)await db.removeChannel(old);
    if(mounted)setState(() {roomId=null;connection=null;});
    await _refresh();
  }
  String money(dynamic cents)=>'${((cents as num? ?? 0)/100).toStringAsFixed(2)} €';
  Future<void> _createRoom() async {
    if(!await _login())return;
    final title=await _ask('Naziv livea');if(title==null)return;
    await live.createRoom(title,'Ostalo');
  }
  Future<void> _publish() async {
    if(!await _login())return;
    final title=await _ask('Naziv predmeta');if(title==null)return;
    final amount=await _ask('Cijena u eurima',hint:'19,90');if(amount==null)return;
    final n=double.tryParse(amount.replaceAll(',','.'));if(n==null||!n.isFinite||n<=0)return;
    await commerce.publish(title,(n*100).round(),1);
  }
  Widget _card(Widget child)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:child));
  @override
  Widget build(BuildContext context) {
    final room=rooms.where((r)=>r['id']==roomId).firstOrNull;
    final host=uid!=null&&room?['host_id']==uid;
    return Scaffold(
      appBar: AppBar(title:Text(room?['title'] as String? ?? 'Online trgovina'),
        leading: roomId==null?null:IconButton(icon:const Icon(Icons.arrow_back),onPressed:_leave),
        actions:[if(uid==null)TextButton(onPressed:_login,child:const Text('Prijava')),
          IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),
      body: Column(children:[
        if(busy)const LinearProgressIndicator(),
        if(failed)MaterialBanner(content:const Text('Online trgovina trenutačno nije dostupna.'),
          actions:[TextButton(onPressed:_refresh,child:const Text('Pokušaj ponovno'))]),
        Expanded(child: loading?const Center(child:CircularProgressIndicator()):
          roomId!=null?_room(room,host):_lobby()),
      ]),
      bottomNavigationBar: roomId!=null?null:NavigationBar(selectedIndex:tab,
        onDestinationSelected:(v){setState(()=>tab=v);_refresh();},
        destinations:const [NavigationDestination(icon:Icon(Icons.live_tv),label:'Uživo'),
          NavigationDestination(icon:Icon(Icons.storefront),label:'Katalog'),
          NavigationDestination(icon:Icon(Icons.receipt_long),label:'Narudžbe')]),
    );
  }
  Widget _lobby()=>ListView(padding:const EdgeInsets.all(16),children:[
    if(tab==0)...[
      FilledButton.icon(onPressed:busy?null:()=>_run(_createRoom),icon:const Icon(Icons.videocam),label:const Text('Pokreni svoj live')),
      if(rooms.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Trenutno nema liveova.')),
      for(final r in rooms) if(r['status']!='ended')_card(ListTile(
        title:Text(r['title'] as String),subtitle:Text(r['status']=='live'?'Uživo':'Uskoro'),
        trailing:const Icon(Icons.play_circle_outline),onTap:()=>_open(r['id'] as String))),
    ],
    if(tab==1)...[
      FilledButton.icon(onPressed:busy?null:()=>_run(_publish),icon:const Icon(Icons.add),label:const Text('Dodaj predmet')),
      for(final p in products)_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(p['title'] as String,style:Theme.of(context).textTheme.titleMedium),Text(money(p['price_cents'])),
        if(p['seller_id']!=uid)FilledButton(onPressed:busy||p['stock']==0?null:()=>_run(()async{
          if(!await _login())return;
          await commerce.reserve(p['id'] as String,1,const Uuid().v4());
          if(mounted)setState(()=>tab=2);
        }),child:Text(p['stock']==0?'Prodano':'Kupi')),
      ])),
    ],
    if(tab==2)...[
      if(uid==null)FilledButton(onPressed:_login,child:const Text('Prijavi se za narudžbe')),
      if(uid!=null)OutlinedButton(onPressed:busy?null:()=>_run(()=>StripeBackend(db).connectSeller()),child:const Text('Postavi Stripe račun prodavatelja (test)')),
      for(final o in orders)_order(o),
    ],
  ]);
  Widget _order(Map<String,dynamic> o) {
    final buyer=o['buyer_id']==uid;final id=o['id'] as String;final state=o['status'];
    const labels={'awaiting_payment':'Čeka plaćanje','paid':'Plaćeno','shipped':'Poslano','delivered':'Dostavljeno','cancelled':'Otkazano','refunded':'Vraćeno'};
    return _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${buyer?'Kupnja':'Prodaja'} · ${money(o['total_cents'])}',style:Theme.of(context).textTheme.titleMedium),
      Text(labels[state]??'$state'),Text('Narudžba ${id.substring(0,8)}'),
      if(buyer&&(state=='awaiting_payment'||state=='paid'))OutlinedButton(onPressed:busy?null:()=>_run(()async{
        final locker=await _ask('BOX NOW paketomat',hint:'ID paketomata');if(locker==null)return;
        await commerce.chooseShipping(id,'boxnow',{'locker_id':locker});
      }),child:const Text('Odaberi paketomat')),
      if(buyer&&state=='awaiting_payment')FilledButton(onPressed:busy?null:()=>_run(()=>StripeBackend(db).checkout(id)),child:const Text('Plati preko Stripea (test)')),
      if(!buyer&&state=='paid')FilledButton(onPressed:busy?null:()=>_run(()async{
        final tracking=await _ask('Broj za praćenje');if(tracking==null)return;
        await commerce.ship(id,'BOX NOW',tracking);
      }),child:const Text('Označi poslano')),
      if(buyer&&state=='shipped')FilledButton(onPressed:busy?null:()=>_run(()=>commerce.confirmDelivery(id)),child:const Text('Potvrdi primitak')),
    ]));
  }
  Widget _room(Map<String,dynamic>? room,bool host)=>Column(children:[
    SizedBox(height:220,child:connection==null?Center(child:TextButton(onPressed:_video,child:const Text('Uključi prijenos'))):
      CloudLiveMedia(key:ValueKey('$roomId:$uid'),connection:connection!)),
    if(host)Wrap(spacing:8,children:[
      if(room?['status']=='scheduled')TextButton(onPressed:()=>_run(()async{await live.setStatus(roomId!,'live');await _video();}),child:const Text('Započni live')),
      TextButton(onPressed:()=>_run(()async{final name=await _ask('Naziv aukcijskog predmeta');if(name!=null)await live.addLot(roomId!,name,100,100);}),child:const Text('Dodaj predmet od 1 €')),
      TextButton(onPressed:()=>_run(()=>live.setStatus(roomId!,'ended')),child:const Text('Završi live')),
    ]),
    Expanded(child:ListView(padding:const EdgeInsets.symmetric(horizontal:16),children:[
      for(final lot in lots)_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(lot['title'] as String,style:Theme.of(context).textTheme.titleMedium),
        Text(money(lot['price_cents']??lot['start_cents'])),
        if(lot['status']=='running')Text('Završava: ${DateTime.tryParse(lot['ends_at'] as String? ?? '')?.toLocal()??''}'),
        if(host&&lot['status']=='queued')TextButton(onPressed:busy?null:()=>_run(()=>live.startLot(lot['id'] as String,30)),child:const Text('Pokreni 30 s')),
        if(!host&&lot['status']=='running')FilledButton(onPressed:busy?null:()=>_run(()async{
          if(!await _login())return;
          final price=lot['price_cents'] as int?;
          await live.bid(lot['id'] as String,price==null?lot['start_cents'] as int:price+(lot['increment_cents'] as int),const Uuid().v4());
        }),child:Text(uid==null?'Prijavi se za licitiranje':'Licitiraj')),
        if(uid!=null&&lot['status']=='running')TextButton(onPressed:busy?null:()=>_run(()=>live.finishLot(lot['id'] as String)),child:const Text('Provjeri rezultat')),
        if(lot['status']=='sold'&&lot['winner_id']==uid)FilledButton(onPressed:busy?null:()=>_run(()async{
          await commerce.claimAward(lot['id'] as String,const Uuid().v4());
          await _leave();if(mounted)setState(()=>tab=2);await _refresh();
        }),child:const Text('Osvojeno · odaberi dostavu')),
      ])),
      const Text('Chat',style:TextStyle(fontWeight:FontWeight.bold)),
      for(final m in messages.reversed)ListTile(dense:true,
        title:Text(m['deleted']==true?'Poruka je uklonjena':m['body'] as String),
        subtitle:Text(m['sender_id']==uid?'Ti':'Korisnik ${(m['sender_id'] as String).substring(0,6)}'),
        trailing:host?PopupMenuButton<String>(onSelected:(v)=>_run(()async{
          if(v=='delete')await live.deleteMessage(m['id'] as int);
          else await live.moderate(roomId!,m['sender_id'] as String,muted:v=='mute',banned:v=='ban');
        }),itemBuilder:(_)=>const[PopupMenuItem(value:'delete',child:Text('Ukloni poruku')),PopupMenuItem(value:'mute',child:Text('Utišaj')),PopupMenuItem(value:'ban',child:Text('Zabrani pristup'))]):null),
    ])),
    SafeArea(top:false,child:Padding(padding:EdgeInsets.fromLTRB(12,6,12,MediaQuery.viewInsetsOf(context).bottom>0?6:12),child:Row(children:[
      Expanded(child:TextField(controller:input,readOnly:uid==null,onTap:uid==null?_login:null,maxLength:500,
        decoration:InputDecoration(hintText:uid==null?'Prijavi se za komentar':'Napiši komentar',counterText:''))),
      IconButton(onPressed:busy?null:()=>_run(()async{if(!await _login())return;final text=input.text.trim();if(text.isEmpty)return;
        await live.sendMessage(roomId!,text,const Uuid().v4());input.clear();}),icon:const Icon(Icons.send)),
    ]))),
  ]);
}
