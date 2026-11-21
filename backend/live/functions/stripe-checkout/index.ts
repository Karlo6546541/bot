import { response } from '../_shared/stripe.ts';
// Existing bookmarks cannot bypass saved-card payments or delayed transfers.
Deno.serve((req:Request)=>req.method==='OPTIONS'?response(200,{}):response(410,{error:'USE_SAVED_CARD'}));

