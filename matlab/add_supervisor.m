function chart = add_supervisor(sys, name, params, pos)
% DISCRETE / SampleTime=100 ns を明示する。計時は temporal logic の duration を使う。
load_system('sflib');
blk = [sys '/' name];
add_block('sflib/Chart', blk, 'Position', pos);
rt = sfroot;
chart = rt.find('-isa', 'Stateflow.Chart', 'Path', blk);
assert(isscalar(chart), 'talkrtl:Supervisor', 'Stateflow chart not found: %s', blk);
chart.ChartUpdate = 'DISCRETE';
chart.SampleTime = num2str(params.clk_period);
% t=0 で OFF を確定し、最初の sample から通常の遷移規則を適用する。
chart.ExecuteAtInitialization = true;

rstd = mkdata(chart, 'rst', 'Input', 'boolean', 1);
end_ = mkdata(chart, 'en', 'Input', 'boolean', 2);
pgd = mkdata(chart, 'pg_cmp', 'Input', 'boolean', 3);
assert(~isempty(rstd) && ~isempty(end_) && ~isempty(pgd), 'talkrtl:Supervisor', 'inputs');
mkdata(chart, 'pgood', 'Output', 'double', 1);
mkdata(chart, 'state', 'Output', 'double', 2);

off = mkstate(chart, 'OFF', sprintf('OFF\nen: pgood = 0; state = 0;'), [120 300 230 120]);
wait = mkstate(chart, 'WAIT', sprintf('WAIT\nen: pgood = 0; state = 1;'), [650 300 230 120]);
on = mkstate(chart, 'ON', sprintf('ON\nen: pgood = 1; state = 2;'), [1180 300 230 120]);

d = Stateflow.Transition(chart);
d.Destination = off;

geopath(chart, off, wait, '[en && !rst]', 1, 3, 9);

% WAIT では rst / en=0 を qualification timeout より優先する。
geopath(chart, wait, off, '[rst]', 1, 9, 3);
geopath(chart, wait, off, '[!en]', 2, 9, 3);
geopath(chart, wait, on, ...
    sprintf('[duration(pg_cmp, sec) >= %.17g]', (params.pg_stable_cycles - 0.5) * params.clk_period), 3, 3, 9);

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
