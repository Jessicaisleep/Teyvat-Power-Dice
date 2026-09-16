/* =====================================================================
   验证「开始游戏.html」里真正发货的那份代码
   ===================================================================== */
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync('开始游戏.html', 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.log('❌ 找不到 <script> 块'); process.exit(1); }
const code = m[1];

/* ---------- 1. 语法 ---------- */
try { new vm.Script(code, { filename: 'game.js' }); console.log('✅ 完整 script 语法检查通过'); }
catch (e) { console.log('❌ 语法错误：' + e.message); process.exit(1); }

/* ---------- 2. DOM 交叉引用 ---------- */
const declared = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(x => x[1]));
const used = new Set([...code.matchAll(/\$\('([^']+)'\)/g)].map(x => x[1]));
const missing = [...used].filter(x => !declared.has(x));
if (missing.length) { console.log('❌ JS 引用了不存在的元素 id：' + missing.join(', ')); process.exit(1); }
console.log(`✅ DOM 交叉引用通过（${used.size} 个 id 全部存在）`);
for (const need of ['s-menu','s-mode','s-codex','s-story','s-select','s-start','s-coin','s-board','codexGrid','storyBar','stGo','hpTop','hpBot','avTop','avBot','avMiniTop','avMiniBot','avaLayer','bgLayer','uiLayer','hotAce','hotReroll','hotOk','stageDice','poolRow','bigVal','midBox']) {
  if (!declared.has(need)) { console.log(`❌ 缺少界面元素 ${need}`); process.exit(1); }
}
console.log('✅ 画面与棋盘元素齐全');

/* ---------- 3. 抽逻辑段 ---------- */
const cut = code.indexOf('const $ = id =>');
if (cut < 0) { console.log('❌ 找不到逻辑段分界'); process.exit(1); }
const logic = code.slice(0, cut);
const ctx = { console, Math, JSON, Set, Object, Array, Number, String };
vm.createContext(ctx);
vm.runInContext(logic + `
;globalThis.__L = { TUNE, LEYLINES, CARDS, ACES, IDS, mkSide, buildPool, rollPool,
  autoSelect, resolve, applyAce, sumDice, aiWantReroll };`, ctx);
const L = ctx.__L;
console.log(`✅ 逻辑段加载成功（${L.IDS.length} 张卡 / 地脉 ${Object.keys(L.LEYLINES).length} 种）`);

/* ---------- 4. AI vs AI（发货逻辑） ---------- */
function playGame(youId, aiId, diff, ley, diffAi) {
  const { TUNE, ACES, CARDS, mkSide, buildPool, rollPool, autoSelect, resolve, applyAce, aiWantReroll } = L;
  TUNE.leyline = ley;
  TUNE.aceUses = ley === 'fengqi' ? 1 : ley === 'shenjing' ? 0 : 2;
  TUNE.rerolls = 1;

  const you = mkSide(youId, true), ai = mkSide(aiId, false);
  if ((diffAi || diff) === 'crazy') { ai.maxHp += 3; ai.hp += 3; }
  for (const s of [you, ai]) {
    if (ley === 'pingyong') { s.maxHp += 4; s.hp += 4; }
    if (ley === 'yanmai') s.shield = 4;
    if (ley === 'shenjing') s.aceLeft = 0;
  }
  const starter = Math.random() < 0.5 ? 0 : 1;
  const second = starter === 0 ? ai : you;
  second.maxHp += TUNE.secondHp; second.hp += TUNE.secondHp;

  let atk = starter, rounds = 0;

  /* 与游戏 selectPhase 的 AI 分支一致：投池 -> 王牌骰 -> 重投 -> 自动选最高 cap 颗 */
  const phase = (A, D, dice, kind, df) => {
    const isAtk = kind === 'atk';
    const cap = CARDS[A.id][isAtk ? 'atkCap' : 'defCap'];
    autoSelect(dice, cap);
    let rerolls = TUNE.rerolls;
    if (ACES[A.id].type === kind && A.aceLeft > 0 && df !== 'easy') {
      applyAce(A.id, dice); A.aceLeft--; autoSelect(dice, cap);
    }
    while (rerolls > 0 && aiWantReroll(A, D, dice, df, isAtk)) {
      rerolls--;
      const sel = dice.filter(d => d.sel !== false);
      const low = sel.filter(d => d.v < (d.f + 1) / 2);
      const targets = (df !== 'easy' && df !== 'normal' && low.length) ? low : sel;
      targets.forEach(d => { d.v = 1 + Math.floor(Math.random() * d.f); });
      autoSelect(dice, cap);
    }
    return dice.filter(d => d.sel !== false);
  };

  while (you.hp > 0 && ai.hp > 0 && rounds < 300) {
    rounds++;
    const A = atk === 0 ? you : ai, D = atk === 0 ? ai : you;
    const useXiao = A.id === 'xiao' && (diff === 'crazy' ? A.hp > TUNE.xiaoSelf + 1 : A.hp > TUNE.xiaoSelf + 4);
    const pool = buildPool(A, 'atk', useXiao);
    const raidenExtra = (A.id === 'raiden') ? 1 : 0;   // 仅用于事件文案，不影响数值
    const xiaoBurst = (A.id === 'xiao' && A.xiaoStreak >= 3) ? TUNE.xiaoBurst : 0;
    const aDice = phase(A, D, rollPool(pool), 'atk', diff);
    const dDice = phase(D, A, rollPool(buildPool(D, 'def', false)), 'def', diffAi || diff);
    const r = resolve(A, D, aDice, dDice, { xiaoBurst, raidenExtra });
    if (you.hp <= 0 || ai.hp <= 0) break;
    if (!r.hold) atk = 1 - atk;
  }
  return { rounds, draw: !(you.hp <= 0 || ai.hp <= 0), win: ai.hp <= 0,
           firstWin: starter === 0 ? (ai.hp <= 0) : (you.hp <= 0) };
}

function sweep(diff, ley) {
  const N = 1200, win = {};   // 12 对手 x 1200 = 每张卡 14400 局, SE ~0.42%
  for (const id of L.IDS) win[id] = 0;
  let draws = 0, total = 0, totR = 0, firstWins = 0;
  for (const a of L.IDS) for (const b of L.IDS) {
    if (a === b) continue;
    for (let g = 0; g < N; g++) {
      const r = playGame(a, b, diff, ley);
      total++; totR += r.rounds;
      if (r.draw) { draws++; continue; }
      if (r.win) win[a]++;
      if (r.firstWin) firstWins++;
    }
  }
  const played = (L.IDS.length - 1) * N;
  const rows = L.IDS.map(id => ({ id, wr: win[id] / played })).sort((x, y) => y.wr - x.wr);
  const wrs = rows.map(r => r.wr);
  const bad = rows.filter(r => r.wr < 0.45 || r.wr > 0.55);
  return { rows, wrs, bad, draws, total, totR, firstWins };
}

for (const diff of ['easy', 'hard']) {
  const s = sweep(diff, null);
  console.log(`\n【发货代码 · AI ${diff === 'easy' ? '简单' : '困难'}】${s.total} 局，平均 ${(s.totR / s.total).toFixed(1)} 回合，` +
    `平局 ${s.draws}，先手方胜率 ${(s.firstWins / (s.total - s.draws) * 100).toFixed(1)}%`);
  console.log('  ' + s.rows.map(r => `${L.CARDS[r.id].name} ${(r.wr * 100).toFixed(1)}%`).join('  '));
  console.log(`  胜率区间 ${(Math.min(...s.wrs) * 100).toFixed(1)}% ~ ${(Math.max(...s.wrs) * 100).toFixed(1)}%  ` +
    (s.bad.length ? '❌ ' + s.bad.map(r => L.CARDS[r.id].name).join('/') : '✅ 全部 45~55%'));
}

console.log('\n【地脉异常 · 困难档】');
for (const ley of Object.keys(L.LEYLINES)) {
  const s = sweep('hard', ley);
  console.log(`  ${L.LEYLINES[ley].name}  ${(Math.min(...s.wrs) * 100).toFixed(1)}% ~ ${(Math.max(...s.wrs) * 100).toFixed(1)}%  ` +
    `均 ${(s.totR / s.total).toFixed(1)} 回合  先手 ${(s.firstWins / (s.total - s.draws) * 100).toFixed(0)}%  ` +
    (s.bad.length ? '⚠ ' + s.bad.map(r => L.CARDS[r.id].name).join('/') : '✅'));
}
console.log('\n✅ 发货代码可完整跑完对局，无运行时错误');


/* ---------- 6. crazy tier check: same character, you=crazy vs ai=hard ---------- */
console.log('');
console.log('[Tier check] same char, you=hard(human) vs ai=crazy (>50% means crazy AI is stronger)');
let cw = 0, cd = 0, ct = 0;
for (const id of L.IDS) {
  let w = 0, n = 0;
  for (let g = 0; g < 400; g++) {
    const r = playGame(id, id, 'hard', null, 'crazy');
    n++;
    if (r.draw) { cd++; continue; }
    if (!r.win) w++;
  }
  cw += w; ct += n;
  console.log('  ' + L.CARDS[id].name.padEnd(6, ' ') + ' crazy-AI ' + (w / n * 100).toFixed(1) + '%');
}
const cwr = cw / (ct - cd);
console.log('  total ' + (cwr * 100).toFixed(1) + '%  ' + (cwr > 0.52 ? 'OK: crazy is stronger' : 'WARN: crazy ~= hard'));