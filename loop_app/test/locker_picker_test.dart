import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/services/delivery_locations.dart';
import 'package:loop_app/widgets/locker_picker.dart';
import 'package:loop_app/widgets/delivery_choice.dart';
const _location=DeliveryLocation(id:'private-location-id',name:'BOX NOW Sesvete',address:'Zagrebačka 162b',postalCode:'10360',city:'Sesvete',country:'HR');
void main(){
 testWidgets('search starts at buyer address and stale responses cannot replace new results',(tester)async{
  final old=Completer<List<DeliveryLocation>>();
  final queries=<String>[];
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:LockerPicker(address:'Stara adresa Zagreb',search:(query){queries.add(query);return queries.length==1?old.future:Future.value([_location]);}))));
  await tester.enterText(find.byKey(const ValueKey('locker-search')),'10360');
  await tester.pump(const Duration(milliseconds:350));
  await tester.pumpAndSettle();
  expect(queries,['Stara adresa Zagreb','10360']);
  expect(find.text('BOX NOW Sesvete'),findsOneWidget);
  expect(find.text('private-location-id'),findsNothing);
  old.complete([]);await tester.pumpAndSettle();
  expect(find.text('BOX NOW Sesvete'),findsOneWidget);
 });
 testWidgets('database failure can be retried without payment or entering an ID',(tester)async{
  var attempts=0;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:LockerPicker(address:'',search:(_)async{if(++attempts==1)throw StateError('offline');return [_location];}))));
  await tester.pumpAndSettle();
  expect(find.text('Pokušaj ponovno'),findsOneWidget);
  await tester.tap(find.text('Pokušaj ponovno'));await tester.pumpAndSettle();
  expect(find.text('BOX NOW Sesvete'),findsOneWidget);
 });
 testWidgets('orders courier choice returns address without a charge action',(tester)async{
  DeliveryDestination? result;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(ctx)=>TextButton(onPressed:()async{result=await showDeliveryChoice(ctx,address:'Kupac 4, Zagreb',search:(_)async=>[_location]);},child:const Text('Dostava'))))));
  await tester.tap(find.text('Dostava'));await tester.pumpAndSettle();
  await tester.tap(find.text('Spremi dostavu'));await tester.pumpAndSettle();
  expect(result?.method,'courier');expect(result?.data,{'address':'Kupac 4, Zagreb'});
  expect(tester.takeException(),isNull);
 });
}
