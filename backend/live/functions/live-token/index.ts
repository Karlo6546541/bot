import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
import { AccessToken } from 'npm:livekit-server-sdk@2.13.3';

// Deploy with Supabase gateway JWT verification ON. No service-role key is needed.
Deno.serve(async (req: Request) => {
  const origin = Deno.env.get('APP_ORIGIN') ?? '';
  const headers = { 'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin',
    'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
  const reply = (status: number, data: unknown) => new Response(JSON.stringify(data), { status, headers });
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const auth = req.headers.get('Authorization');
    if (!auth?.startsWith('Bearer ')) return reply(401, { error: 'AUTH_REQUIRED' });
    const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: { user }, error } = await client.auth.getUser();
    if (error || !user) return reply(401, { error: 'AUTH_REQUIRED' });
    const { roomId } = await req.json();
    if (typeof roomId !== 'string' || !/^[0-9a-f-]{36}$/i.test(roomId)) return reply(400, { error: 'INVALID_ROOM' });
    const { data: allowed, error: accessError } = await client.rpc('live_can_join', { p_room: roomId });
    if (accessError || !allowed) return reply(403, { error: 'ACCESS_DENIED' });
    const { data: room } = await client.from('live_rooms').select('host_id,status').eq('id', roomId).single();
    if (!room || room.status !== 'live') return reply(409, { error: 'ROOM_NOT_LIVE' });
    const host = room.host_id === user.id;
    const token = new AccessToken(Deno.env.get('LIVEKIT_API_KEY')!, Deno.env.get('LIVEKIT_API_SECRET')!,
      { identity: user.id, ttl: '5m' });
    token.addGrant({ roomJoin: true, room: `live-${roomId}`, canPublish: host,
      canSubscribe: true, canPublishData: false });
    return reply(200, { token: await token.toJwt(), url: Deno.env.get('LIVEKIT_URL'),
      room: `live-${roomId}`, role: host ? 'host' : 'viewer' });
  } catch {
    return reply(500, { error: 'TOKEN_UNAVAILABLE' });
  }
});
