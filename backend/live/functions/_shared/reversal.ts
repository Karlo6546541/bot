import { services } from './stripe.ts';
export async function reverseSellerTransfer(svc:Awaited<ReturnType<typeof services>>,payment:{order_id:string;transfer_id:string}) {
 const transfer=await svc.stripe.transfers.retrieve(payment.transfer_id);
 if(transfer.amount>transfer.amount_reversed)await svc.stripe.transfers.createReversal(transfer.id,{amount:transfer.amount-transfer.amount_reversed},{idempotencyKey:`risk-reversal-${transfer.id}`});
 const {error}=await svc.admin.from('commerce_payments').update({released_at:null}).eq('order_id',payment.order_id);
 if(error)throw error;
}
