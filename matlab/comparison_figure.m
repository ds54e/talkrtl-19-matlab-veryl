function info = comparison_figure(io)
% comparison の発表用 figure を MATLAB で生成する。GUI 操作は要らない。
% SDI session とは別に、スライドへそのまま貼れる overview 図を 1 枚作る。
%
%   overview.png     : 上段 vout (reference vs implementation)、下段
%                      pg_cmp / pgood / en / load_hi を 1 signal 1 row の compact な
%                      timing 表示で
%
% time shift も plot 用 smoothing もしない。
s = io.paths();
if ~isfolder(s.comparison_dir), mkdir(s.comparison_dir); end

a0 = io.readcsv(s.reference_analog);
a1 = io.readcsv(fullfile(s.verilator_dir, 'rnm_nominal_full.csv'));
d0 = io.readcsv(s.reference_digital);
d1 = io.readcsv(fullfile(s.verilator_dir, 'system_nominal.csv'));

t_a0 = a0.t_s * 1e6;           % us
t_a1 = a1.time_ns / 1e3;       % us
t_d0 = d0.time_ns / 1e3;       % us
t_d1 = d1.time_ns / 1e3;       % us
% reference の digital.csv は DUT 出力だけを持つ (stimulus を含まない) ので、
% scenario は reference 側の analog.csv と implementation 側の rnm_nominal.csv から取る。
a1n = io.readcsv(fullfile(s.verilator_dir, 'rnm_nominal.csv'));
t_s0 = a0.t_s * 1e6;
t_s1 = a1n.time_ns / 1e3;

c0 = [0.000 0.447 0.741];      % reference
c1 = [0.850 0.325 0.098];      % implementation

% ---------------- overview -----------------------------------------------
% 上段 vout (reference vs implementation) を dominant に置き、その下へ digital /
% stimulus を 1 signal 1 row の compact な timing 表示で積む。binary signal に
% 広い縦幅は要らないので、各 row は vout panel よりずっと低くする。
% solid = reference、dashed/dotted = implementation (vout panel の legend と同じ約束)。
f1 = figure('Visible', 'off', 'Position', [100 100 1100 840], 'Color', 'w');

AX_L = 0.072;                  % 全 panel 共通の左端 / 幅 (x 軸を揃える)
AX_W = 0.895;
H_VOUT = 0.345;                % vout panel は digital row の約 4 倍の高さ
H_DIG = 0.082;
GAP = 0.038;

ax_v = axes(f1, 'Position', [AX_L 0.590 AX_W H_VOUT]);
plot(ax_v, t_a0, a0.vout, '-', 'Color', c0, 'LineWidth', 1.1); hold(ax_v, 'on');
plot(ax_v, t_a1, a1.vout, '--', 'Color', c1, 'LineWidth', 1.1);
grid(ax_v, 'on');
ylabel(ax_v, 'vout [V]');
title(ax_v, 'Reference vs implementation — nominal 50 us');
legend(ax_v, {'Reference: Simscape + Stateflow', 'Implementation: Verilator RNM + Veryl'}, ...
    'Location', 'southeast');
ylim(ax_v, [0 1.08]);

% 1 signal = 1 row。{ylabel, reference trace, implementation trace}。en は reference
% のみ (implementation と tick 厳密一致で重なるため 1 本にまとめる)。data は上と同じ column。
rows = {
    'pg\_cmp',  {t_d0, d0.pg_cmp, '-', c0}, ...
                {t_d1, d1.pg_cmp, '--', c1}
    'pgood',    {t_d0, d0.pgood, '-', [0.000 0.600 0.200]}, ...
                {t_d1, d1.pgood, '--', [0.700 0.200 0.600]}
    'en',       {t_s0, a0.en, '-', [0.300 0.300 0.300]}, ...
                {}
    'load\_hi', {t_s0, a0.load_hi, '-', [0.800 0.500 0.000]}, ...
                {t_s1, a1n.load_hi, ':', [0.200 0.200 0.200]}
    };
for k = 1:size(rows, 1)
    y = 0.120 + (size(rows, 1) - k) * (H_DIG + GAP);
    ax = axes(f1, 'Position', [AX_L y AX_W H_DIG]);
    tr = rows{k, 2};
    stairs(ax, tr{1}, tr{2}, tr{3}, 'Color', tr{4}, 'LineWidth', 1.1);
    hold(ax, 'on');
    tr = rows{k, 3};
    if ~isempty(tr)
        stairs(ax, tr{1}, tr{2}, tr{3}, 'Color', tr{4}, 'LineWidth', 1.1);
    end
    grid(ax, 'on');
    ylim(ax, [-0.15 1.15]);
    yticks(ax, [0 1]);
    ylabel(ax, rows{k, 1}, 'FontSize', 9);
    set(ax, 'FontSize', 9);
    if k < size(rows, 1)
        xticklabels(ax, {});     % 時刻軸は最下段だけに出す (timing 表示らしく)
    else
        xlabel(ax, 'time [us]');
    end
end

exportgraphics(f1, s.figure, 'Resolution', 140);
close(f1);

info = struct();
info.overview = s.figure;
info.overview_bytes = dir(info.overview).bytes;
end
