import 'package:flutter/material.dart';
import '../services/delivery_locations.dart';
import '../theme/app_theme.dart';
import 'locker_picker.dart';

Future<DeliveryDestination?> showDeliveryChoice(BuildContext context, {
  required String address,
  required Future<List<DeliveryLocation>> Function(String) search,
}) => showModalBottomSheet<DeliveryDestination>(
  context: context, isScrollControlled: true, showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 520),
  backgroundColor: LoopColors.background,
  builder: (_) => _DeliveryChoice(address: address,search: search),
);
class _DeliveryChoice extends StatefulWidget {
 const _DeliveryChoice({required this.address,required this.search});
 final String address;
 final Future<List<DeliveryLocation>> Function(String) search;
 @override
 State<_DeliveryChoice> createState()=>_DeliveryChoiceState();
}
class _DeliveryChoiceState extends State<_DeliveryChoice> {
 late final controller=TextEditingController(text:widget.address);
 bool courier=true;
 DeliveryLocation? locker;
 String? error;
 @override
 void dispose(){controller.dispose();super.dispose();}
 @override
 Widget build(BuildContext ctx) => appThemed(SafeArea(
      child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(20,0,20,20+MediaQuery.viewInsetsOf(ctx).bottom),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
        Row(children:[const Expanded(child:Text('Odaberi dostavu',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900))),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))]),
        Wrap(spacing:8,children:[
          ChoiceChip(label:const Text('Paketomat'),selected:!courier,onSelected:(_)=>setState((){courier=false;error=null;})),
          ChoiceChip(label:const Text('Kurirska dostava'),selected:courier,onSelected:(_)=>setState((){courier=true;error=null;})),
        ]),
        if(courier) TextField(controller:controller,decoration:const InputDecoration(labelText:'Adresa za dostavu'),maxLines:3,minLines:1)
        else ListTile(contentPadding:EdgeInsets.zero,title:Text(locker?.name??'Odaberi paketomat'),subtitle:Text(locker?.label??'Pretraži prema svojoj adresi'),trailing:const Icon(Icons.chevron_right),onTap:()async{
          final picked=await showLockerPicker(ctx,address:controller.text,search:widget.search,selected:locker);
          if(ctx.mounted&&picked!=null){setState((){locker=picked;error=null;});}
        }),
        if(error!=null)Text(error!,style:TextStyle(color:LoopColors.error)),
        const SizedBox(height:16),
        FilledButton(onPressed:(){
          if(courier&&controller.text.trim().isEmpty){setState(()=>error='Upiši adresu za dostavu.');return;}
          if(!courier&&locker==null){setState(()=>error='Odaberi paketomat za dostavu.');return;}
          Navigator.pop(ctx,courier?DeliveryDestination.courier(controller.text.trim()):DeliveryDestination.locker(locker!));
        },child:const Text('Spremi dostavu')),
      ])),
    ));
}
