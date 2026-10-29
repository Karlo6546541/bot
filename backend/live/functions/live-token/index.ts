import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
import { AccessToken } from 'npm:livekit-server-sdk@2.13.3';

// Public viewer endpoint: verify user JWT here when supplied. Never trust a role from the client.
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
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const hasUserToken = !!auth && auth !== `Bearer ${anonKey}` && !auth.startsWith('Bearer sb_publishable_');
    if (hasUserToken && !auth!.startsWith('Bearer ')) return reply(401, { error: 'INVALID_AUTH' });
    const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: hasUserToken ? { Authorization: auth! } : {} }, auth: { persistSession: false } });
    let userId: string | null = null;
    if (hasUserToken) {
      const { data: { user }, error } = await client.auth.getUser();
      if (error || !user) return reply(401, { error: 'INVALID_AUTH' });
      userId = user.id;
    }
    const { roomId } = await req.json();
    if (typeof roomId !== 'string' || !/^[0-9a-f-]{36}$/i.test(roomId)) return reply(400, { error: 'INVALID_ROOM' });
    const { data: allowed, error: accessError } = await client.rpc('live_can_join', { p_room: roomId });
    if (accessError || !allowed) return reply(403, { error: 'ACCESS_DENIED' });
    const { data: room } = await client.from('live_rooms').select('host_id,status').eq('id', roomId).single();
    if (!room || room.status !== 'live') return reply(409, { error: 'ROOM_NOT_LIVE' });
    const host = userId !== null && room.host_id === userId;
    const token = new AccessToken(Deno.env.get('LIVEKIT_API_KEY')!, Deno.env.get('LIVEKIT_API_SECRET')!,
      { identity: userId ?? `guest-${crypto.randomUUID()}`, ttl: '5m' });
    token.addGrant({ roomJoin: true, room: `live-${roomId}`, canPublish: host,
      canSubscribe: true, canPublishData: false });
    return reply(200, { token: await token.toJwt(), url: Deno.env.get('LIVEKIT_URL'),
      room: `live-${roomId}`, role: host ? 'host' : 'viewer' });
  } catch {
    return reply(500, { error: 'TOKEN_UNAVAILABLE' });
  }
});
