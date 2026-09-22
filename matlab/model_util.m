function u = model_util()
u.libblk = @libblk;
u.addss = @addss;
u.newsub = @newsub;
u.p = @p;
u.conn = @conn;
u.conns = @conns;
u.pname = @pname;
u.addport = @addport;
u.subport = @subport;
u.addpgcmp = @addpgcmp;
u.logsignal = @logsignal;
u.addconst = @addconst;
end

function path = libblk(lib, name)
% library block名には改行を含むものがあるため、名前で実物から解決する。
hits = find_system(lib, 'LookUnderMasks', 'all', 'Name', name);
assert(isscalar(hits), 'talkrtl:ModelUtil', 'library block not unique: %s / %s', lib, name);
path = hits{1};
end

function blk = addss(container, lib, name, blkName, pos)
blk = [container '/' blkName];
add_block(libblk(lib, name), blk, 'Position', pos);
end

function blk = newsub(sys, name, pos)
blk = [sys '/' name];
add_block('simulink/Ports & Subsystems/Subsystem', blk, 'Position', pos);
lines = find_system(blk, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'line');
if ~isempty(lines), delete_line(lines); end
for pname = {'In1', 'Out1'}
    child = [blk '/' pname{1}];
    if getSimulinkBlockHandle(child) ~= -1, delete_block(child); end
end
end

function h = p(container, blk, field, idx)
h = get_param([container '/' blk], 'PortHandles').(field)(idx);
end

function conn(container, a, b)
add_line(container, a, b, 'autorouting', 'smart');
end

function conns(container, a, b)
% subsystem の physical port handle は遅延するため、外側の network は名前で結ぶ。
add_line(container, a, b, 'autorouting', 'smart');
end

function name = pname(container, subName, portBlock)
% subsystem の物理接続port名 (例 'Rdiv/LConn1') を内部 PMIOPort の Port 番号から作る。
n = str2double(get_param([container '/' subName '/' portBlock], 'Port'));
assert(~isnan(n), 'talkrtl:ModelUtil', 'bad port number for %s/%s', subName, portBlock);
name = sprintf('%s/LConn%d', subName, n);
end

function blk = addport(container, name, num, pos)
% 物理接続port (PMIOPort) を作る。subsystem 側には LConn<num> として現れる。
% R2026a では Side は Left 固定で、番号は Port で指定する。
u = model_util();
blk = [container '/' name];
add_block(u.libblk('nesl_utility', 'Connection Port'), blk, ...
    'Port', num2str(num), 'Position', pos);
got = str2double(get_param(blk, 'Port'));
assert(got == num, 'talkrtl:ModelUtil', ...
    'connection port %s numbered %d, expected %d', name, got, num);
end

function h = subport(subsys, portBlock)
% subsystem の物理接続portを、内部 PMIOPort block の Port 番号から解決する。
n = str2double(get_param([subsys '/' portBlock], 'Port'));
assert(~isnan(n), 'talkrtl:ModelUtil', 'bad port number for %s/%s', subsys, portBlock);
h = get_param(subsys, 'PortHandles').LConn(n);
end

function blk = addpgcmp(sys, name, params, pos)
% strict hysteresis: >0.87 で set、<0.85 で clear、等値は hold。
% R2026a の Simulink Relay は等値で切り替わるため使わない。
u = model_util();
blk = u.newsub(sys, name, pos);
add_block('simulink/Sources/In1', [blk '/vout'], 'Position', [20 120 50 150]);
add_block('simulink/Logic and Bit Operations/Relational Operator', [blk '/rise'], ...
    'Operator', '>', 'OutDataTypeStr', 'boolean', 'Position', [140 60 190 100]);
add_block('simulink/Logic and Bit Operations/Relational Operator', [blk '/fall'], ...
    'Operator', '<', 'OutDataTypeStr', 'boolean', 'Position', [140 200 190 240]);
u.addconst(blk, 'pg_high', num2str(params.pg_high), [30 230 80 260]);
u.addconst(blk, 'pg_low', num2str(params.pg_low), [30 300 80 330]);
add_block('simulink/Logic and Bit Operations/Logical Operator', [blk '/not_fall'], ...
    'Operator', 'NOT', 'Position', [250 200 280 240]);
add_block('simulink/Logic and Bit Operations/Logical Operator', [blk '/hold_high'], ...
    'Operator', 'AND', 'Inputs', '2', 'Position', [330 180 370 240]);
add_block('simulink/Logic and Bit Operations/Logical Operator', [blk '/next'], ...
    'Operator', 'OR', 'Inputs', '2', 'Position', [420 100 460 160]);
add_block('simulink/Discrete/Memory', [blk '/prev'], 'InitialCondition', '0', ...
    'Position', [330 300 370 340]);
add_block('simulink/Signal Attributes/Data Type Conversion', [blk '/to_double'], ...
    'OutDataTypeStr', 'double', 'Position', [510 110 560 150]);
add_block('simulink/Sinks/Out1', [blk '/pg_cmp'], 'Position', [620 115 650 145]);
u.conn(blk, u.p(blk, 'vout', 'Outport', 1), u.p(blk, 'rise', 'Inport', 1));
u.conn(blk, u.p(blk, 'pg_high', 'Outport', 1), u.p(blk, 'rise', 'Inport', 2));
u.conn(blk, u.p(blk, 'vout', 'Outport', 1), u.p(blk, 'fall', 'Inport', 1));
u.conn(blk, u.p(blk, 'pg_low', 'Outport', 1), u.p(blk, 'fall', 'Inport', 2));
u.conn(blk, u.p(blk, 'fall', 'Outport', 1), u.p(blk, 'not_fall', 'Inport', 1));
u.conn(blk, u.p(blk, 'prev', 'Outport', 1), u.p(blk, 'hold_high', 'Inport', 1));
u.conn(blk, u.p(blk, 'not_fall', 'Outport', 1), u.p(blk, 'hold_high', 'Inport', 2));
u.conn(blk, u.p(blk, 'rise', 'Outport', 1), u.p(blk, 'next', 'Inport', 1));
u.conn(blk, u.p(blk, 'hold_high', 'Outport', 1), u.p(blk, 'next', 'Inport', 2));
u.conn(blk, u.p(blk, 'next', 'Outport', 1), u.p(blk, 'prev', 'Inport', 1));
u.conn(blk, u.p(blk, 'next', 'Outport', 1), u.p(blk, 'to_double', 'Inport', 1));
u.conn(blk, u.p(blk, 'to_double', 'Outport', 1), u.p(blk, 'pg_cmp', 'Inport', 1));
end

function addconst(container, name, value, pos)
add_block('simulink/Sources/Constant', [container '/' name], 'Value', value, 'Position', pos);
end

function logsignal(container, blk, portIdx, name)
% 信号名を付け、SDI streaming を有効にする。logsout の element 名は信号名になる。
u = model_util();
h = u.p(container, blk, 'Outport', portIdx);
set_param(h, 'Name', name);
Simulink.sdi.markSignalForStreaming([container '/' blk], portIdx, 'on');
end
