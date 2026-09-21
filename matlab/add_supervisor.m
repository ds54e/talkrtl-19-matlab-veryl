function chart = add_supervisor(sys, name, params, pos)
% CONTRACT.md §4 の OFF/WAIT/ON supervisor を Stateflow chart として作る。
% DISCRETE / SampleTime=100 ns を明示する。計時は temporal logic の duration を使う。
% 描画geometryは意味に影響しないため、失敗しても遷移の意味は変えない。
load_system('sflib');
blk = [sys '/' name];
add_block('sflib/Chart', blk, 'Position', pos);
rt = sfroot;
chart = rt.find('-isa', 'Stateflow.Chart', 'Path', blk);
assert(isscalar(chart), 'talkrtl:Supervisor', 'Stateflow chart not found: %s', blk);
chart.ChartUpdate = 'DISCRETE';
chart.SampleTime = num2str(params.clk_period);
% 初期状態 OFF を t=0 の初期化で確定させ、最初のサンプルから CONTRACT の
% per-sample 規則 (en=1 かつ pg_cmp=0 なら WAIT) を適用できるようにする。
chart.ExecuteAtInitialization = true;

rstd = mkdata(chart, 'rst', 'Input', 'boolean', 1);
end_ = mkdata(chart, 'en', 'Input', 'boolean', 2);
pgd = mkdata(chart, 'pg_cmp', 'Input', 'boolean', 3);
assert(~isempty(rstd) && ~isempty(end_) && ~isempty(pgd), 'talkrtl:Supervisor', 'inputs');
mkdata(chart, 'pgood', 'Output', 'double', 1);
mkdata(chart, 'state', 'Output', 'double', 2);

off = mkstate(chart, 'OFF', sprintf('OFF\nen: pgood = 0; state = 0;'), [40 40 160 120]);
wait = mkstate(chart, 'WAIT', sprintf('WAIT\nen: pgood = 0; state = 1;'), [320 260 440 340]);
on = mkstate(chart, 'ON', sprintf('ON\nen: pgood = 1; state = 2;'), [640 40 760 120]);

% 初期遷移: OFF が既定。
d = Stateflow.Transition(chart);
d.Destination = off;

% OFF -> WAIT: rst が無効で en=1 になった tick で WAIT へ入る。
% CONTRACT の優先順位では rst/en が最優先で、en=1 かつ pg_cmp=0 は WAIT である。
% High を観測した tick がそのまま k0 になる。
geopath(chart, off, wait, '[en && !rst]', 1, 3, 9);

% WAIT の優先順位: rst, en=0, 期限。期限到達より前の2つを優先する。
geopath(chart, wait, off, '[rst]', 1, 9, 3);
geopath(chart, wait, off, '[!en]', 2, 9, 3);
geopath(chart, wait, on, ...
    sprintf('[duration(pg_cmp, usec) >= %d]', params.pg_stable_cycles / 10), 3, 3, 9);

% ON の優先順位: rst, en=0, pg_cmp=0。
geopath(chart, on, off, '[rst]', 1, 9, 3);
geopath(chart, on, off, '[!en]', 2, 9, 3);
geopath(chart, on, wait, '[!pg_cmp]', 3, 3, 3);
end

function d = mkdata(chart, name, scope, type, port)
d = Stateflow.Data(chart);
d.Name = name;
d.Scope = scope;
d.DataType = type;
if strcmp(scope, 'Input') || strcmp(scope, 'Output')
    try
        d.Port = port;
    catch
    end
end
end

function s = mkstate(chart, name, label, pos)
s = Stateflow.State(chart);
s.Name = name;
s.LabelString = label;
s.Position = pos;
end

function geopath(chart, src, dst, label, order, ~, ~)
t = Stateflow.Transition(chart);
t.Source = src;
t.Destination = dst;
t.LabelString = label;
try
    t.ExecutionOrder = order;
catch
end
end
