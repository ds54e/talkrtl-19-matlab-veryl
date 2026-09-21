function result = compare_results(io)
% reference model (MATLAB/Simscape/Stateflow) の fresh 出力と Verilator
% (SV-RNM + Veryl) の出力を比較する。
%
% 許容差は下の定数で固定する。実測後に変更しない。
% digital は 501 tick の完全一致 (許容差 0 / shift 0)。
s = io.paths();

TOL_BASELINE_MV = 1.0;    % pointwise |vout_impl - vout_ref| (baseline 100点)
TOL_SCALAR_MV = 0.1;     % key scalar (mean / heavy minimum / vout max)
TOL_CROSSING_NS = 10.0;  % pg_cmp crossing 時刻差
REFERENCE_MEAN_15_24 = 0.89874047158234394;
REFERENCE_MEAN_32_34 = 0.89255048338733634;
REFERENCE_HEAVY_MIN = 0.84051278286808562;
REFERENCE_VOUT_MAX = 1.0124728454710277;
REFERENCE_CROSSINGS_NS = [4830.0, 25310.0, 26180.0];
REFERENCE_DIRS = [1, -1, 1];

a0 = io.readcsv(s.reference_analog);
a1 = io.readcsv(fullfile(s.verilator_dir, 'rnm_nominal_full.csv'));
d0 = io.readcsv(s.reference_digital);
d1 = io.readcsv(fullfile(s.verilator_dir, 'system_nominal.csv'));

C = {};

% ---------------- analog grid alignment -------------------------------------
t0 = round(a0.t_s * 1e9);          % s -> integer ns
t1 = round(a1.time_ns);
grid_ok = numel(t0) == numel(t1) && isequal(t0, t1);
C = push(C, 'analog.grid_same_10ns', grid_ok, sprintf( ...
    'reference %d samples vs implementation %d samples; identical ns grid = %d', ...
    numel(t0), numel(t1), grid_ok));
if ~grid_ok
    result = finish(C, struct());
    return
end
v0 = a0.vout;
v1 = a1.vout;
p0 = double(a0.pg_cmp);
p1 = double(a1.pg_cmp);

% ---------------- analog pointwise, whole run (informational) ---------------
dv_full = abs(v1 - v0);
full_worst = max(dv_full);
full_at = t0(find(dv_full == full_worst, 1));
C = push(C, 'analog.pointwise_all_samples_reported', true, sprintf( ...
    'max|vout_impl - vout_ref| over all %d samples = %.6f mV at t=%.0f ns (informational, not a gate)', ...
    numel(v1), full_worst * 1e3, full_at));

% ---------------- analog pointwise on the baseline sample points ------------
% baseline の時刻そのもので比較する。time shift も interpolation もしない。
pv = io.readcsv(s.baseline);
pv_idx = [];
pv_t = [];
for k = 1:height(pv)
    tn = round(pv.t_s(k) * 1e9);
    if tn <= 0, continue; end
    i = find(t0 == tn, 1);
    if ~isempty(i)
        pv_idx(end + 1) = i; %#ok<AGROW>
        pv_t(end + 1) = tn; %#ok<AGROW>
    end
end
C = push(C, 'analog.baseline_points_found', numel(pv_idx) == 100, sprintf( ...
    '%d/100 baseline sample points matched exactly on the 10 ns grid', numel(pv_idx)));

if numel(pv_idx) == 100
    i = pv_idx;
    d_fresh = abs(v1(i) - v0(i));
    [wf, wft] = max(d_fresh);
    C = push(C, 'reference.baseline.pointwise_vout_vs_fresh', wf * 1e3 <= TOL_BASELINE_MV, sprintf( ...
        'max|vout_impl - vout_ref(fresh)| = %.6f mV at t=%.0f ns (limit %.1f mV)', ...
        wf * 1e3, pv_t(wft), TOL_BASELINE_MV));

    pvv = pv.vout;
    keep = false(height(pv), 1);
    for k = 1:height(pv)
        keep(k) = round(pv.t_s(k) * 1e9) > 0;
    end
    pvv = pvv(keep);
    d_comm = abs(v1(i) - pvv);
    [wc, wct] = max(d_comm);
    C = push(C, 'reference.baseline.pointwise_vout_vs_committed', wc * 1e3 <= TOL_BASELINE_MV, sprintf( ...
        'max|vout_impl - vout_ref(committed)| = %.6f mV at t=%.0f ns (limit %.1f mV)', ...
        wc * 1e3, pv_t(wct), TOL_BASELINE_MV));

    d_ref = abs(v0(i) - pvv);
    [wg, wgt] = max(d_ref);
    C = push(C, 'reference.baseline.fresh_equals_committed', wg * 1e3 <= TOL_BASELINE_MV, sprintf( ...
        'max|vout_ref(fresh) - vout_ref(committed)| = %.6f mV at t=%.0f ns (diagnostic: reference did not move)', ...
        wg * 1e3, pv_t(wgt)));
    baseline = struct('points', numel(i), 'worst_vs_fresh_mV', wf * 1e3, ...
        'worst_vs_fresh_at_ns', pv_t(wft), 'worst_vs_committed_mV', wc * 1e3, ...
        'worst_vs_committed_at_ns', pv_t(wct), 'worst_fresh_vs_committed_mV', wg * 1e3);
else
    baseline = struct('points', numel(pv_idx));
end

% ---------------- analog key scalars ----------------------------------------
m15_1 = mean(v1(t1 >= 15000 & t1 <= 24000));
m32_1 = mean(v1(t1 >= 32000 & t1 <= 34000));
sel = t1 >= 25000 & t1 <= 35000;
[hmin_1, hi] = min(v1(sel));
th = t1(sel);
hmin_at_1 = th(hi);
vmax_1 = max(v1);
m15_0 = mean(v0(t0 >= 15000 & t0 <= 24000));
m32_0 = mean(v0(t0 >= 32000 & t0 <= 34000));
sel0 = t0 >= 25000 & t0 <= 35000;
hmin_0 = min(v0(sel0));
vmax_0 = max(v0);

C = push(C, 'reference.scalar.mean_15_24us', abs(m15_1 - REFERENCE_MEAN_15_24) * 1e3 <= TOL_SCALAR_MV, sprintf( ...
    'impl %.14f vs reference %.14f -> %.6f mV (limit %.1f mV); fresh reference %.14f', ...
    m15_1, REFERENCE_MEAN_15_24, abs(m15_1 - REFERENCE_MEAN_15_24) * 1e3, TOL_SCALAR_MV, m15_0));
C = push(C, 'reference.scalar.mean_32_34us', abs(m32_1 - REFERENCE_MEAN_32_34) * 1e3 <= TOL_SCALAR_MV, sprintf( ...
    'impl %.14f vs reference %.14f -> %.6f mV (limit %.1f mV); fresh reference %.14f', ...
    m32_1, REFERENCE_MEAN_32_34, abs(m32_1 - REFERENCE_MEAN_32_34) * 1e3, TOL_SCALAR_MV, m32_0));
C = push(C, 'reference.scalar.heavy_load_min', abs(hmin_1 - REFERENCE_HEAVY_MIN) * 1e3 <= TOL_SCALAR_MV, sprintf( ...
    'impl %.14f at t=%.0f ns vs reference %.14f -> %.6f mV (limit %.1f mV); fresh reference %.14f', ...
    hmin_1, hmin_at_1, REFERENCE_HEAVY_MIN, abs(hmin_1 - REFERENCE_HEAVY_MIN) * 1e3, TOL_SCALAR_MV, hmin_0));
C = push(C, 'reference.scalar.vout_max', abs(vmax_1 - REFERENCE_VOUT_MAX) * 1e3 <= TOL_SCALAR_MV, sprintf( ...
    'impl %.14f vs reference %.14f -> %.6f mV (limit %.1f mV); fresh reference %.14f', ...
    vmax_1, REFERENCE_VOUT_MAX, abs(vmax_1 - REFERENCE_VOUT_MAX) * 1e3, TOL_SCALAR_MV, vmax_0));

% ---------------- pg_cmp crossings ------------------------------------------
c1 = crossings(t1, p1);
c0 = crossings(t0, p0);
% 注意: c1 は struct なので numel(c1) は 1。transition 数は numel(c1.t)。
C = push(C, 'cmp.transition_count', numel(c1.t) == 3, sprintf( ...
    'impl %d transitions (want 3); fresh reference %d', numel(c1.t), numel(c0.t)));
C = push(C, 'cmp.transition_directions', isequal(c1.dir, REFERENCE_DIRS), sprintf( ...
    'impl directions [%s] (want rise/fall/rise); fresh reference [%s]', ...
    strjoin(dirstr(c1.dir), ','), strjoin(dirstr(c0.dir), ',')));
C = push(C, 'cmp.count_and_direction_match_fresh_reference', ...
    numel(c1.t) == numel(c0.t) && isequal(c1.dir, c0.dir), sprintf( ...
    'impl %d/%s vs fresh reference %d/%s', numel(c1.t), strjoin(dirstr(c1.dir), ','), ...
    numel(c0.t), strjoin(dirstr(c0.dir), ',')));

worst_ref = 0; detail_ref = {};
for k = 1:min(numel(c1.t), numel(REFERENCE_CROSSINGS_NS))
    dt = abs(c1.t(k) - REFERENCE_CROSSINGS_NS(k));
    worst_ref = max(worst_ref, dt);
    detail_ref{end + 1} = sprintf('%.3f us vs reference %.3f us (d=%.0f ns)', ...
        c1.t(k) / 1e3, REFERENCE_CROSSINGS_NS(k) / 1e3, dt); %#ok<AGROW>
end
C = push(C, 'cmp.crossing_time_diff_vs_reference', ...
    numel(c1.t) == 3 && worst_ref <= TOL_CROSSING_NS, sprintf( ...
    'worst %.0f ns (limit %.0f ns) :: %s', worst_ref, TOL_CROSSING_NS, strjoin(detail_ref, '; ')));

worst_fresh = 0; detail_fresh = {};
for k = 1:min(numel(c1.t), numel(c0.t))
    dt = abs(c1.t(k) - c0.t(k));
    worst_fresh = max(worst_fresh, dt);
    detail_fresh{end + 1} = sprintf('%.3f/%.3f us d=%.0f ns', ...
        c1.t(k) / 1e3, c0.t(k) / 1e3, dt); %#ok<AGROW>
end
C = push(C, 'cmp.crossing_time_diff_vs_fresh_reference', ...
    numel(c1.t) == numel(c0.t) && worst_fresh <= TOL_CROSSING_NS, sprintf( ...
    'worst %.0f ns (limit %.0f ns) :: %s', worst_fresh, TOL_CROSSING_NS, strjoin(detail_fresh, '; ')));

analog = struct('samples', numel(v1), 'grid_ns', 10, ...
    'pointwise_all_mV', full_worst * 1e3, 'pointwise_all_at_ns', full_at, ...
    'baseline', baseline, ...
    'mean_15_24us', m15_1, 'mean_15_24us_ref', REFERENCE_MEAN_15_24, ...
    'mean_15_24us_diff_mV', abs(m15_1 - REFERENCE_MEAN_15_24) * 1e3, ...
    'mean_32_34us', m32_1, 'mean_32_34us_ref', REFERENCE_MEAN_32_34, ...
    'mean_32_34us_diff_mV', abs(m32_1 - REFERENCE_MEAN_32_34) * 1e3, ...
    'heavy_min', hmin_1, 'heavy_min_at_ns', hmin_at_1, 'heavy_min_ref', REFERENCE_HEAVY_MIN, ...
    'heavy_min_diff_mV', abs(hmin_1 - REFERENCE_HEAVY_MIN) * 1e3, ...
    'vout_max', vmax_1, 'vout_max_ref', REFERENCE_VOUT_MAX, ...
    'vout_max_diff_mV', abs(vmax_1 - REFERENCE_VOUT_MAX) * 1e3, ...
    'pg_cmp_crossings_ns', c1.t, 'pg_cmp_directions', c1.dir, ...
    'pg_cmp_crossings_reference_ns', c0.t, ...
    'worst_crossing_diff_vs_reference_ns', worst_ref, ...
    'worst_crossing_diff_vs_fresh_reference_ns', worst_fresh, ...
    'fresh_reference_mean_15_24us', m15_0, 'fresh_reference_mean_32_34us', m32_0, ...
    'fresh_reference_heavy_min', hmin_0, 'fresh_reference_vout_max', vmax_0);

% ---------------- digital: 501 ticks, exact, no shift ------------------------
C = push(C, 'digital.row_count', height(d0) == 501 && height(d1) == 501, sprintf( ...
    'reference %d rows, implementation %d rows (want 501)', height(d0), height(d1)));

fields = {'tick', 'rst', 'en', 'pg_cmp', 'state', 'pgood'};
mm = struct();
all_exact = height(d0) == 501 && height(d1) == 501;
for k = 1:numel(fields)
    f = fields{k};
    x = double(d0.(f));
    y = double(d1.(f));
    if numel(x) ~= numel(y)
        mm.(f) = NaN;
        all_exact = false;
        continue
    end
    n = sum(x ~= y);
    mm.(f) = n;
    if n ~= 0, all_exact = false; end
    C = push(C, ['digital.' f '_exact'], n == 0, sprintf( ...
        '%s: %d/%d mismatched ticks (tolerance 0, shift 0)', f, n, numel(x)));
end

C = push(C, 'digital.grid_ns', all(round(d0.time_ns) == round(d1.time_ns)), sprintf( ...
    'tick time grid identical: 0..%g ns step %g ns', d0.time_ns(end), d0.time_ns(2) - d0.time_ns(1)));

digital = struct('ticks', 501, 'tick_ns', 100, 'mismatch_by_field', mm, ...
    'exact', all_exact, ...
    'reference_pgood_transition_ticks', transitions_ticks(d0.pgood), ...
    'implementation_pgood_transition_ticks', transitions_ticks(d1.pgood), ...
    'reference_pg_cmp_transition_ticks', transitions_ticks(d0.pg_cmp), ...
    'implementation_pg_cmp_transition_ticks', transitions_ticks(d1.pg_cmp));

result = finish(C, struct('analog', analog, 'digital', digital));
end

% ---------------------------------------------------------------------------

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
c.dir = d(idx)';
c.dir = c.dir(:)';
end

function s = dirstr(d)
s = cell(1, numel(d));
for k = 1:numel(d)
    if d(k) > 0, s{k} = 'rise'; else, s{k} = 'fall'; end
end
end

function ticks = transitions_ticks(x)
idx = find(diff(double(x)) ~= 0);
ticks = idx;
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
