const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

const html = readFileSync(new URL('../app/index.html', 'file://' + __filename), 'utf8');
const script = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)]
  .map(match => match[1]).filter(text => text.trim()).join('\n');
const helpers = script.slice(script.indexOf('const WEEKEND_CAP_MIN'), script.indexOf('/* ===== 티켓 타이머'));
const buyItem = script.slice(script.indexOf('async function buyItem('), script.indexOf('async function useTicket('));
const day = '2026-11-05';
const now = '2026-11-06T01:00:00Z';
const item = { id: 'game', weekend_only: true, timer_minutes: null };

function client(status) {
  const kids = ['first', 'second', 'third'].map(id => ({ id, role: 'child' }));
  const messages = [];
  const context = vm.createContext({
    Date: class extends Date { static now() { return Date.parse(now); } },
    STATE: {
      items: [item], tickets: [],
      noSchoolDays: status ? [{ day_date: day, status, requested_by: 'first' }] : [],
    },
    USERS: kids, ME: kids[1], item,
    nameOf: () => '은아', esc: value => value,
    $: () => ({ value: day }), isParent: () => false,
    toast: (_, message) => messages.push(message),
    guard: fn => fn(),
  });
  vm.runInContext(helpers + buyItem, context);
  return { context, messages, run: source => vm.runInContext(source, context) };
}

test('the inline client script parses', () => {
  new vm.Script(script);
});

test('New York date and Friday cutoff use family time in winter and summer', () => {
  const { run } = client();
  assert.equal(run('nyDayKey()'), day);
  assert.equal(run("isShopWeekend('2026-11-06T22:59:00Z')"), false);
  assert.equal(run("isShopWeekend('2026-11-06T23:00:00Z')"), true);
  assert.equal(run("isShopWeekend('2026-07-10T22:00:00Z')"), true);
  assert.equal(run("isShopWeekend('2026-11-07T18:00:00Z')"), true);
  assert.equal(run("isShopWeekend('2026-11-08T18:00:00Z')"), true);
});

test('a sibling sees who requested the date and the handler refuses a duplicate', async () => {
  const { run, messages } = client('pending');
  assert.match(run('childNoSchoolCard(nyDayKey())'), /id="noSchoolSubmit" disabled/);
  await run('requestNoSchoolDay()');
  assert.match(messages[0], /은아.*이미 신청/);
  assert.equal(run('isShopWeekend()'), false);
});

test('one approval unlocks all three kids and disables repeat requests', () => {
  const { context, run } = client('approved');
  for (const kid of context.USERS) {
    context.ME = kid;
    assert.equal(run('weekendBlock(item)'), null);
  }
  assert.match(run('childNoSchoolCard(nyDayKey())'), /오늘은 학교 없는 날/);
  assert.match(run('childNoSchoolCard(nyDayKey())'), /id="noSchoolSubmit" disabled/);
});

test('denial allows a new request', () => {
  const { run } = client('denied');
  assert.equal(run('noSchoolFeedback(nyDayKey())'), '');
});

test('daily cap uses NY date, preserves weekday exceptions, and ignores gold', () => {
  const { run } = client();
  run('ME.settings={weekday_ok:true,daily_cap_min:60}');
  assert.equal(run('weekendBlock(item)'), null);
  run('STATE.noSchoolDays=[{day_date:nyDayKey(),status:"approved"}]');
  run('STATE.tickets=[{child_id:ME.id,item_id:item.id,purchased_at:new Date(Date.now()).toISOString(),paid_gold:true}]');
  assert.equal(run('weekendBlock(item)'), null);
  run('STATE.tickets[0].paid_gold=false');
  assert.equal(run('weekendBlock(item).why'), 'cap');
});

test('buyItem refuses a weekday purchase before balance checks or writes', async () => {
  const { run, messages } = client();
  await run('buyItem(item.id)');
  assert.match(messages[0], /주말이나 승인된 학교 없는 날/);
});

test('a concurrent request conflict refreshes the picker and identifies the requester', async () => {
  const { context, run, messages } = client();
  context.sb = { from: () => ({ insert: async () => ({ error: { code: '23505' } }) }) };
  context.refresh = async () => {
    context.STATE.noSchoolDays = [{ day_date: day, status: 'pending', requested_by: 'first' }];
  };
  await run('requestNoSchoolDay()');
  assert.match(messages[0], /은아.*이미 신청/);
  assert.match(run('childNoSchoolCard(nyDayKey())'), /id="noSchoolSubmit" disabled/);
});

test('buyItem refunds the debit when the database rejects the ticket', async () => {
  const { context, run, messages } = client('approved');
  const stampEvents = [];
  context.STATE.items = [{ ...item, name: '게임', cost: 2 }];
  Object.assign(context, {
    bal: () => 10, activeWarns: () => [], activeSads: () => [], activeFines: () => [],
    confirm: () => true, refresh: async () => {},
    sb: {
      from(table) {
        return {
          select: () => ({
            eq: (...args) => args[0] === 'child_id' && table === 'fam_stamp_events'
              ? { data: [{ delta: 10 }] }
              : { eq: () => ({ count: 0 }) },
          }),
          insert: async row => {
            if (table === 'fam_tickets') return { error: { message: 'weekend_cap_exceeded' } };
            assert.equal(table, 'fam_stamp_events');
            stampEvents.push(row.delta);
            return {};
          },
        };
      },
    },
  });
  await run('buyItem(item.id)');
  assert.deepEqual(stampEvents, [-2, 2]);
  assert.match(messages[0], /120분.*돌려놨어요/);
});
