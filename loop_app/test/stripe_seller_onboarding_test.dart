import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/services/stripe_backend.dart';
import 'package:loop_app/models/seller_info.dart';

void main(){
 final seller=SellerInfo(legalName:'Test Seller',oib:'12345678903',address:'Ulica 1, 10000 Zagreb',iban:'HR1723600001101234565',birthDate:DateTime(1990,1,1),updatedAt:DateTime(2026));
 test('ready sellers continue without a redirect and send no payout account or tax number',()async{
  var launches=0;
  final client=SupabaseClient('https://test.invalid','test-key',httpClient:MockClient((request)async{
   expect(request.url.path,'/functions/v1/stripe-connect');
   final body=jsonDecode(request.body) as Map;
   expect(body['action'],'ensure');expect(body['country'],'HR');
   expect(body['seller']['legalName'],'Test Seller');
   expect((body['seller'] as Map).containsKey('iban'),false);
   expect((body['seller'] as Map).containsKey('oib'),false);
   expect(body.containsKey('account'),false);
   return http.Response('{"ready":true,"mode":"test"}',200,headers:{'content-type':'application/json'});
  }));
  final ready=await StripeBackend(client,sellerLauncher:(_)async{launches++;return true;}).ensureSellerReady(seller,country:'HR');
  expect(ready,true);expect(launches,0);await client.dispose();
 });
 test('unfinished seller opens the returned Stripe form and cannot continue selling yet',()async{
  Uri? launched;
  final client=SupabaseClient('https://test.invalid','test-key',httpClient:MockClient((_)async=>http.Response('{"ready":false,"url":"https://connect.stripe.com/setup/test"}',200,headers:{'content-type':'application/json'})));
  expect(await StripeBackend(client,sellerLauncher:(url)async{launched=url;return true;}).ensureSellerReady(seller,country:'HR'),false);
  expect(launched?.host,'connect.stripe.com');await client.dispose();
 });
 test('untrusted onboarding URL cannot redirect a seller',()async{
  var launches=0;
  final client=SupabaseClient('https://test.invalid','test-key',httpClient:MockClient((_)async=>http.Response('{"ready":false,"url":"https://example.invalid/fake"}',200,headers:{'content-type':'application/json'})));
  await expectLater(StripeBackend(client,sellerLauncher:(_)async{launches++;return true;}).ensureSellerReady(seller,country:'HR'),throwsStateError);
  expect(launches,0);await client.dispose();
 });
}

