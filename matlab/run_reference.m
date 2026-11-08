function reference_id = run_reference()
s = demo_paths();
fprintf('=== reference: Simscape LDO + Stateflow supervisor ===\n');
Simulink.sdi.clear();
load_system(s.model_file);

% Root inputs are en, load_hi, rst. SimulationInput leaves the saved model intact.
t = (0:10e-9:50e-6)';
en = double(t >= 2e-6);
load_hi = double(t >= 25e-6 & t < 35e-6);
input = Simulink.SimulationInput('ldo_demo');
input = input.setExternalInput([t, en, load_hi, zeros(size(t))]);
out = sim(input);
for name = {'vout', 'vfb', 'vctrl', 'ipass', 'pg_cmp', 'pgood', 'state', ...
        'en', 'load_hi', 'rst'}
    S.(name{1}) = out.logsout.get(name{1}).Values;
end

if ~isfolder(s.reference_dir), mkdir(s.reference_dir); end
at = S.vout.Time;
analog = table(at, pickconst(S.en, at), pickconst(S.load_hi, at), ...
    S.vout.Data, pickconst(S.vfb, at), pickconst(S.vctrl, at), ...
    pickconst(S.ipass, at), pickconst(S.pg_cmp, at), ...
    'VariableNames', {'t_s', 'en', 'load_hi', 'vout', 'vfb', 'vctrl', 'ipass', 'pg_cmp'});
writetable(analog, s.reference_analog);

dt = S.pgood.Time;
digital = table((0:numel(dt)-1)', dt * 1e9, ...
    round(pickconst(S.rst, dt)), round(pickconst(S.en, dt)), ...
    round(pickconst(S.pg_cmp, dt)), round(S.state.Data), round(S.pgood.Data), ...
    round(pickconst(S.load_hi, dt)), ...
    'VariableNames', {'tick', 'time_ns', 'rst', 'en', 'pg_cmp', 'state', 'pgood', 'load_hi'});
writetable(digital, s.reference_digital);
ids = Simulink.sdi.getAllRunIDs();
reference_id = ids(end);
end

function v = pickconst(ts, times)
% Logged constants may contain only one sample; hold every signal between samples.
if all(ts.Data == ts.Data(1))
    v = repmat(ts.Data(1), numel(times), 1);
else
    idx = arrayfun(@(tq) find(ts.Time <= tq + 1e-15, 1, 'last'), times);
    v = ts.Data(idx);
end
end
