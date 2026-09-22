function result = run_comparison()
io = comparison_io();
s = io.paths();

required = {s.reference_analog, s.reference_digital, s.reference_session, ...
    fullfile(s.verilator_dir, 'rnm_nominal_full.csv'), ...
    fullfile(s.verilator_dir, 'rnm_nominal.csv'), ...
    fullfile(s.verilator_dir, 'system_nominal.csv')};
missing = {};
for k = 1:numel(required)
    if ~isfile(required{k}), missing{end + 1} = required{k}; end %#ok<AGROW>
end
assert(isempty(missing), 'talkrtl:Comparison', ...
    ['comparison の入力がありません:\n  %s\n' ...
    'reference 再生成 : bash tools/matlab-batch.sh "addpath(''matlab''); run_reference"\n' ...
    'Verilator        : ./tools/run-verilator.sh'], strjoin(missing, '\n  '));

result = struct('phase', 'comparison', 'pass', false);

fprintf('=== comparison ===\n');
result.comparison = compare_results(io);

fprintf('=== comparison SDI session ===\n');
result.sdi = comparison_sdi(io);

fprintf('=== comparison figure ===\n');
result.figure = comparison_figure(io);

figs_ok = isfield(result.figure, 'overview') && isfile(result.figure.overview);
result.pass = strcmp(result.comparison.verdict, 'PASS') && ...
    strcmp(result.sdi.verdict, 'PASS') && figs_ok;

io.json(s.result, result);
fprintf('comparison: COMPARISON=%s SDI=%s FIGURES=%s : %s\n', ...
    result.comparison.verdict, result.sdi.verdict, tf(figs_ok), tf(result.pass));
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
