import { createServer } from 'node:http';
import { readFileSync, mkdirSync, appendFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { defineTool } from '@deepseek-ai/dsh-tools';
import { createUserMessage } from '@deepseek-ai/dsh-llm';
import { installModelSelection } from '@deepseek-ai/dsh-agent';
import { DecisionBinding } from './decision_binding.mjs';

export const name = 'isaac-strategy';
export const inject = ['agents', 'agentLoop', 'tools', 'systemPrompt', 'sessions'];
export function apply(ctx, config = {}) {
  const endpoint = config.endpoint ?? 'http://127.0.0.1:9532';
  if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(endpoint)) throw new Error('Isaac bridge must use IPv4 loopback');
  const token = process.env.ISAAC_BRIDGE_TOKEN;
  if (!token) throw new Error('ISAAC_BRIDGE_TOKEN required');
  const instructions = readFileSync(fileURLToPath(new URL('./instructions.md', import.meta.url)), 'utf8');
  const logs = config.logs;
  if (logs) mkdirSync(logs, {recursive: true});
  const metrics = {ready: false, dshVersion: '0.2.2-rc.1', provider: 'isaac-lan', model: 'gpt-6-luna',
    turns: 0, toolCalls: 0, failures: 0, lastDecision: null, latencyMs: [], toolNames: [], lastError: null};
  let handle, agent, busy = false, timer, server, disposed = false, automatic = false;
  let lastDecision = null;
  let turnsInSession = 0;
  const binding = new DecisionBinding();
  const record = (kind, data = {}) => {
    if (logs) appendFileSync(`${logs}/dsh-events.jsonl`, JSON.stringify({at: new Date().toISOString(), kind, ...data})+'\n');
  };
  record('mounting',{pid:process.pid});
  async function bridge(path, body, signal) {
    const combined = signal ? AbortSignal.any([signal, AbortSignal.timeout(1800)]) : AbortSignal.timeout(1800);
    const response = await fetch(endpoint+path, {method: body === undefined ? 'GET' : 'POST', signal: combined,
      headers: {'Content-Type': 'application/json', 'X-Isaac-Token': token},
      body: body === undefined ? undefined : JSON.stringify(body)});
    const result = await response.json();
    if (!response.ok) throw new Error(result.error ?? `Local bridge ${response.status}`);
    return result;
  }
  const tools = [
    ['isaac_get_state', '实时查询角色生命、完整背包、房间、已发现地图、层级、敌人与 boss。含新鲜度，未知不猜测。',
      {topic:{type:'string',enum:['state','health','inventory','effects','history','actives','pockets','map','room','enemies','bosses','pickups','resources']}},
      (a,e)=>bridge('/query?topic='+encodeURIComponent(a.topic??'state'), undefined, e.signal)],
    ['isaac_get_decision', '读取或刷新待判断集合、可选 offer、上下文身份和剩余时间；事件已附决策时无需重复查询。', {},
      async(a,e)=>binding.bind(await bridge('/decision', undefined, e.signal))],
    ['isaac_lookup', '查询本地版本化道具/卡牌机制和 12 类策略规则；unknown 表示不能凭空推断。',
      {kind:{type:'string',required:true,enum:['collectible','card','domain']},id:{type:'string',required:true}},
      (a,e)=>bridge('/lookup?kind='+encodeURIComponent(a.kind)+'&id='+encodeURIComponent(a.id), undefined, e.signal)],
    ['isaac_submit_plan', '从有效 offer 选择一个有期限的意图；本地会复核资源、身份、价格与安全。成功提交即结束本轮。',
      {offer_ref:{type:'string',required:true},reason:{type:'string',required:true},execution_seconds:{type:'number'},
       budget:{type:'object',required:true,additionalProperties:false,properties:{
         coins:{type:'integer',required:true},keys:{type:'integer',required:true},bombs:{type:'integer',required:true},
         health_half_hearts:{type:'integer',required:true}}}},
      async(a,e)=>{ const result=await bridge('/plan',binding.plan(a),e.signal); e.concludeTurn(); return result; }],
  ];
  for (const [toolName, description, parameters, execute] of tools) {
    ctx.tools.register(defineTool({name:toolName,description,parameters,
      output:{schema:{type:'json'},render:(_a,value)=>[{type:'text',text:JSON.stringify(value)}]},
      async execute(args, exec) {
        const start=performance.now(); metrics.toolCalls++; metrics.toolNames.push(toolName);
        try { const result=await execute(args,exec); record('tool',{name:toolName,elapsedMs:performance.now()-start,
          ...(toolName==='isaac_submit_plan'?{receipt:result}:{})}); return result; }
        catch(error) { record('tool_error',{name:toolName,message:String(error.message).slice(0,300)}); throw error; }
      }}));
  }
  async function drive(prompt, deadlineMs = 25000) {
    if (busy) throw new Error('One strategic turn is already running');
    busy=true; binding.reset(); const start=performance.now(); let timedOut=false;
    const timeout=setTimeout(()=>{timedOut=true;agent.cancel({kind:'user'});},Math.min(60000,deadlineMs));
    try {
      if(turnsInSession>=4) {
        await handle.dispose();
        await createAgent();
        record('session_rotated',{reason:'bounded_context',sessionId:agent.id});
      }
      turnsInSession++;
      metrics.turns++;
      // Bind the authoritative event before inference. The model can submit in
      // one round trip and still query live state or refresh the decision.
      const decision=await bridge('/decision');
      const view=binding.bind(decision);
      if(!view.pending||!view.connected)throw new Error('No fresh pending decision');
      record('decision_prefetched',{decisionId:decision.id,remainingMs:decision.remaining_ms});
      const eventPrompt=prompt+'\n\n插件已读取并绑定以下当前决策；无需再次调用 isaac_get_decision，信息充分时直接 isaac_submit_plan。需要更新时仍可查询。\n'+JSON.stringify(view);
      agent.followup(createUserMessage({content:[{type:'text',text:eventPrompt}],source:{kind:'user'}}));
      await agent.whenIdle();
      const elapsed=performance.now()-start; metrics.latencyMs.push(elapsed);
      metrics.latencyMs=metrics.latencyMs.slice(-200);
      if(timedOut) throw new Error('Strategic model turn deadline exceeded');
      metrics.lastError=null;
      record('turn_complete',{elapsedMs:elapsed,status:agent.status,sessionId:agent.id});
      return {elapsed_ms:elapsed,status:agent.status,session_id:agent.id,tool_calls:metrics.toolCalls};
    } catch(error) {metrics.failures++;metrics.lastError=String(error.message).slice(0,300);record('turn_error',{message:metrics.lastError});throw error;}
    finally {clearTimeout(timeout);busy=false;}
  }
  async function tick() {
    if(!automatic||busy||disposed||!agent)return;
    try {
      const d=await bridge('/decision');
      if(!d.pending||!d.connected||d.id===lastDecision||d.remaining_ms<1500)return;
      lastDecision=d.id;metrics.lastDecision=d.id;
      await drive(`当前待判断事件 ${d.id}。使用插件附上的当前候选，按收益与生存选择一个 offer 并提交。请在 ${d.remaining_ms} ms 内完成。`,d.remaining_ms);
    } catch(error) {metrics.lastError=String(error.message).slice(0,300);}
  }
  ctx.on('agent/error', ({agent:subject,error})=>{
    if(subject===agent){metrics.failures++;metrics.lastError=String(error.message??error).slice(0,300);record('agent_error',{message:metrics.lastError});}
  });
  async function createAgent() {
    record('agent_creation_started');
    handle=await ctx.agents.create({sessionId:'isaac-'+randomUUID(),meta:{cwd:config.cwd??process.cwd()},
      agentOptions:{provider:'isaac-lan',model:'gpt-6-luna',maxTokens:1400},
      setup(agentCtx,newAgent) {
        installModelSelection(agentCtx);
        agentCtx.systemPrompt.section({name:'isaac-complete',order:0,text:instructions,complete:true});
        agentCtx.tools.restrict({allow:tools.map(t=>t[0])});
      }});
    agent=handle.agent;
    record('agent_creation_finished',{sessionId:agent.id});
    turnsInSession=0;
  }
  async function start() {
    await createAgent();
    server=createServer(async(req,res)=>{
      res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');
      try {
        if(req.method==='GET'&&req.url==='/status') {res.end(JSON.stringify({...metrics,pid:process.pid,busy,automatic,agentStatus:agent.status,sessionId:agent.id}));return;}
        if(req.method!=='POST'||req.headers['x-isaac-token']!==token) {res.statusCode=403;res.end('{"error":"local authorization required"}');return;}
        let input='';for await(const chunk of req){input+=chunk;if(input.length>16384)throw new Error('body too large');}
        const body=JSON.parse(input||'{}');
        if(req.url==='/control') {automatic=body.automatic===true;res.end(JSON.stringify({automatic}));return;}
        if(req.url==='/run') {const result=await drive(body.prompt??'先查询当前决策，再按规则选择并提交。',body.deadline_ms??25000);res.end(JSON.stringify(result));return;}
        if(req.url==='/cancel') {agent.cancel({kind:'user'});automatic=false;res.end('{"cancelled":true}');return;}
        res.statusCode=404;res.end('{"error":"not found"}');
      } catch(error){res.statusCode=400;res.end(JSON.stringify({error:String(error.message).slice(0,300)}));}
    });
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(config.port??9533,'127.0.0.1',resolve);});
    timer=setInterval(tick,250);
    metrics.ready=true;record('ready',{pid:process.pid,profile:'isaac',model:metrics.model,provider:metrics.provider});
    if(logs)writeFileSync(`${logs}/host-ready.json`,JSON.stringify({pid:process.pid,port:config.port??9533,...metrics}));
    console.error('Isaac DSH strategic host ready on loopback '+(config.port??9533));
  }
  start().catch(error=>{metrics.lastError=String(error.message).slice(0,300);record('startup_error',{message:metrics.lastError});console.error('Isaac DSH startup failed: '+metrics.lastError);});
  ctx.on('dispose',()=>{disposed=true;automatic=false;clearInterval(timer);server?.close();handle?.dispose();});
}
