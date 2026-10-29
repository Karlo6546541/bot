import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
import { RoomServiceClient } from 'npm:livekit-server-sdk@2.13.3';
import { authenticate, response } from '../_shared/stripe.ts';
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    await authenticate(req);
    const { roomId, action, userId } = await req.json();
    if (typeof roomId !== 'string' || !['end', 'ban'].includes(action)) return response(400, { error: 'INVALID_ACTION' });
    const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: req.headers.get('Authorization')! } }, auth: { persistSession: false } });
    const { data: host, error: hostError } = await client.rpc('live_is_host', { p_room: roomId });
    if (hostError || !host) return response(403, { error: 'HOST_ONLY' });
    const media = new RoomServiceClient(Deno.env.get('LIVEKIT_URL')!.replace(/^wss:/, 'https:'),
      Deno.env.get('LIVEKIT_API_KEY')!, Deno.env.get('LIVEKIT_API_SECRET')!);
    if (action === 'end') {
      // DB revokes future admission first; then terminate the active SFU room.
      // End must be retryable: an already-ended room still needs SFU cleanup.
      const { data: room } = await client.from('live_rooms').select('status').eq('id', roomId).single();
      if (room?.status !== 'ended') {
        const { error } = await client.rpc('live_set_status', { p_room: roomId, p_status: 'ended' });
        if (error) return response(409, { error: 'FINISH_RUNNING_LOT_FIRST' });
      }
      await media.deleteRoom(`live-${roomId}`);
    } else {
      if (typeof userId !== 'string') return response(400, { error: 'INVALID_USER' });
      const { error } = await client.rpc('live_moderate', { p_room: roomId, p_user: userId, p_muted: true, p_banned: true });
      if (error) return response(403, { error: 'MODERATION_DENIED' });
      // removeParticipant invalidates the participant's current tokens in LiveKit Cloud.
      await media.removeParticipant(`live-${roomId}`, userId);
    }
    return response(200, { ok: true });
  } catch { return response(503, { error: 'LIVE_CONTROL_UNAVAILABLE' }); }
});
