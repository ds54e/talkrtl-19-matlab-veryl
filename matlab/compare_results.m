function result = compare_results(io)
s = io.paths();

TOL_SCALAR_MV = 0.1;
TOL_CROSSING_NS = 10.0;

a0 = io.readcsv(s.reference_analog);
a1 = io.readcsv(fullfile(s.xezim_dir, 'rnm_nominal_full.csv'));
d0 = io.readcsv(s.reference_digital);
d1 = io.readcsv(fullfile(s.xezim_dir, 'system_nominal.csv'));

C = {};
t0 = round(a0.t_s * 1e9);
t1 = round(a1.time_ns);
grid_ok = numel(t0) == numel(t1) && isequal(t0, t1);
C = push(C, 'analog.grid', grid_ok, sprintf('%d/%d samples', numel(t0), numel(t1)));
if ~grid_ok
    result = finish(C, struct());
    return
end

v0 = a0.vout;
v1 = a1.vout;
dv = abs(v1 - v0);
[worst, wi] = max(dv);

m15_0 = mean(v0(t0 >= 15000 & t0 <= 24000));
m15_1 = mean(v1(t1 >= 15000 & t1 <= 24000));
m32_0 = mean(v0(t0 >= 32000 & t0 <= 34000));
m32_1 = mean(v1(t1 >= 32000 & t1 <= 34000));
sel0 = t0 >= 25000 & t0 <= 35000;
sel1 = t1 >= 25000 & t1 <= 35000;
hmin_0 = min(v0(sel0));
hmin_1 = min(v1(sel1));
vmax_0 = max(v0);
vmax_1 = max(v1);

scalar_names = {'mean_15_24us', 'mean_32_34us', 'heavy_min', 'vout_max'};
ref_values = [m15_0, m32_0, hmin_0, vmax_0];
impl_values = [m15_1, m32_1, hmin_1, vmax_1];
for k = 1:numel(scalar_names)
    dmV = abs(impl_values(k) - ref_values(k)) * 1e3;
    C = push(C, ['analog.' scalar_names{k}], dmV <= TOL_SCALAR_MV, sprintf( ...
        'reference %.12g, implementation %.12g, diff %.6f mV', ...
        ref_values(k), impl_values(k), dmV));
end

c0 = crossings(t0, double(a0.pg_cmp));
c1 = crossings(t1, double(a1.pg_cmp));
shape_ok = numel(c0.t) == numel(c1.t) && isequal(c0.dir, c1.dir);
C = push(C, 'pg_cmp.sequence', shape_ok, sprintf( ...
    'reference %d transitions, implementation %d', numel(c0.t), numel(c1.t)));

if shape_ok && ~isempty(c0.t)
    crossing_diff = max(abs(c1.t - c0.t));
else
    crossing_diff = inf;
end
C = push(C, 'pg_cmp.timing', crossing_diff <= TOL_CROSSING_NS, sprintf( ...
    'worst diff %.0f ns', crossing_diff));

digital_grid = height(d0) == 501 && height(d1) == 501 && ...
    isequal(round(d0.time_ns), round(d1.time_ns));
C = push(C, 'digital.grid', digital_grid, sprintf( ...
    'reference %d rows, implementation %d rows', height(d0), height(d1)));

fields = {'tick', 'rst', 'en', 'pg_cmp', 'state', 'pgood'};
mm = struct();
digital_exact = digital_grid;
for k = 1:numel(fields)
    f = fields{k};
    if height(d0) ~= height(d1)
        mm.(f) = NaN;
        digital_exact = false;
    else
        mm.(f) = sum(double(d0.(f)) ~= double(d1.(f)));
        digital_exact = digital_exact && mm.(f) == 0;
    end
end
C = push(C, 'digital.exact', digital_exact, sprintf( ...
    'mismatches tick/rst/en/pg_cmp/state/pgood = %g/%g/%g/%g/%g/%g', ...
    mm.tick, mm.rst, mm.en, mm.pg_cmp, mm.state, mm.pgood));

analog = struct('samples', numel(v1), ...
    'pointwise_max_mV', worst * 1e3, ...
    'pointwise_max_at_ns', t0(wi), ...
    'reference', ref_values, ...
    'implementation', impl_values, ...
    'pg_cmp_crossings_reference_ns', c0.t, ...
    'pg_cmp_crossings_implementation_ns', c1.t, ...
    'worst_crossing_diff_ns', crossing_diff);

digital = struct('ticks', height(d1), 'mismatch_by_field', mm, 'exact', digital_exact);
result = finish(C, struct('analog', analog, 'digital', digital));
end

function C = push(C, name, ok, detail)
C{end + 1} = struct('check', name, 'ok', logical(ok), 'detail', detail);
fprintf('  [%s] %s: %s\n', tf(ok), name, detail);
end

function result = finish(C, extra)
checks = [C{:}];
ok = all([checks.ok]);
f = fieldnames(extra);
for k = 1:numel(f), result.(f{k}) = extra.(f{k}); end
result.checks = checks;
result.failed = {checks(~[checks.ok]).check};
result.verdict = tf(ok);
end

function c = crossings(t, p)
d = diff(p);
idx = find(d ~= 0);
c.t = t(idx + 1);
c.dir = sign(d(idx))';
c.dir = c.dir(:)';
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
