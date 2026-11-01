function info=apply_layout(mdl,file)
% Apply an approved display profile to a structurally matching loaded model.
% The model is not saved. Guards, values, sample times and logging are retained.
if nargin<2
    root=fileparts(fileparts(mfilename('fullpath')));
    file=fullfile(root,'model','layout','approved.json');
end
assert(bdIsLoaded(mdl),'Model must be loaded.');
assert(strcmp(get_param(mdl,'SimulationStatus'),'stopped'),'Stop the simulation first.');
assert(isfile(file),'talkrtl:LayoutFile','Layout file not found: %s',file);
approved=jsondecode(fileread(file));
assert(approved.schema_version==1,'talkrtl:LayoutSchema','Unsupported layout schema.');
current=layout_profile(mdl);
expected=layout_contract(approved);actual=layout_contract(current);
if ~isequal(expected,actual)
    missing=setdiff(expected,actual);extra=setdiff(actual,expected);
    error('talkrtl:LayoutMismatch', ...
        'Model and layout differ (%d missing, %d new items). Review the model and capture a matching layout.\n%s', ...
        numel(missing),numel(extra),strjoin([missing(1:min(3,end)),extra(1:min(3,end))],newline));
end
allowed={'Position','Orientation','BlockMirror','BlockRotation','NamePlacement','ShowName', ...
    'FontName','FontSize','FontWeight','FontAngle','ForegroundColor', ...
    'BackgroundColor','DropShadow','IconShape'};
% Validate every property before any mutations. JSON never supplies callbacks.
for b=approved.blocks(:)'
    assert(all(ismember(fieldnames(b.graphics),allowed)),'talkrtl:LayoutSchema','Non-display block property.');
    r=reshape(b.graphics.Position,1,[]);
    assert(numel(r)==4 && all(isfinite(r)) && r(3)>r(1) && r(4)>r(2), ...
        'talkrtl:LayoutSchema','Invalid block bounds: %s.',b.path);
    assert(ismember(b.graphics.Orientation,{'right','left','up','down'}),'Invalid orientation.');
    assert(isempty(b.port_side) || (strcmp(b.type,'PMIOPort') && ismember(b.port_side,{'Left','Right'})), ...
        'Invalid physical port side.');
end
logicBefore=chartLogic(mdl);
logging=captureLogging(mdl,current.systems);
for b=approved.blocks(:)'
    if ~isempty(b.port_side),set_param(full(mdl,b.path),'Side',b.port_side);end
end
for b=approved.blocks(:)'
    block=full(mdl,b.path);fields=fieldnames(b.graphics);
    fields(strcmp(fields,'Position'))=[];
    % Rotation precedes bounds, so the native rotate operation cannot resize
    % the final rectangle. The approved symbol proportions are preserved.
    fields=[{'BlockMirror';'Orientation'};fields(~ismember(fields,{'Orientation','BlockMirror'}))];
    for field=fields'
        set_param(block,field{1},b.graphics.(field{1}));
    end
    % Orientation is a lossy alias for native rotation/reflection on Simscape
    % icons. Restore these hidden native properties after the generic fields.
    set_param(block,'BlockRotation',b.graphics.BlockRotation,'BlockMirror',b.graphics.BlockMirror);
    set_param(block,'Position',reshape(b.graphics.Position,1,[]));
end
% All geometry has been positioned before any line tree is redrawn.
for s=approved.systems(:)'
    sys=full(mdl,s.path);ports=layout_ports(mdl,sys);
    while true
        ls=find_system(sys,'LookUnderMasks','all','FindAll','on','SearchDepth',1,'Type','line');
        if isempty(ls),break;end
        delete_line(ls(1));
    end
    for net=s.nets(:)'
        for route=net.paths(:)'
            dst=terminal(ports,route.to_port);points=double(route.points);
            if ~isempty(route.from_port)
                src=terminal(ports,route.from_port);
                h=add_line(sys,src,dst,'autorouting','off');
            else
                attach=points;
                attach(end,:)=get_param(dst,'Position');
                h=add_line(sys,attach);
            end
            set_param(h,'Points',points);
        end
    end
    notes=find_system(sys,'FindAll','on','SearchDepth',1,'Type','annotation');
    for h=notes(:)',delete(get_param(h,'Object'));end
    for note=s.annotations(:)'
        obj=Simulink.Annotation(sys,note.text);
        obj.Position=reshape(note.position,1,[]);
    end
    set_param(sys,'ZoomFactor',s.zoom);
end
for c=approved.charts(:)'
    chart=sfroot().find('-isa','Stateflow.Chart','Path',full(mdl,c.path));
    for s=c.states(:)'
        state=chart.find('-isa','Stateflow.State','Name',s.name);
        state.Position=reshape(s.position,1,[]);state.FontSize=s.font_size;
    end
    transitions=chart.find('-isa','Stateflow.Transition');
    for t=c.transitions(:)'
        match=[];
        for tr=transitions(:)'
            src='DEFAULT';if ~isempty(tr.Source),src=tr.Source.Name;end
            if strcmp(src,t.source) && strcmp(tr.Destination.Name,t.destination) && tr.ExecutionOrder==t.order
                match=tr;break
            end
        end
        assert(~isempty(match),'Missing chart edge.');
        match.FontSize=t.font_size;match.ArrowSize=t.arrow_size;
        if isempty(match.Source),match.SourceEndpoint=reshape(t.source_endpoint,1,[]);
        else,match.SourceOClock=t.source_clock;end
        match.DestinationOClock=t.destination_clock;
        match.MidPoint=reshape(t.midpoint,1,[]);
        r=match.LabelPosition;match.LabelPosition=[reshape(t.label_position,1,[]) r(3:4)];
    end
    % Restore the persisted viewport as well as its scale. Editor.ZoomFactor
    % alone can be recalculated from a fresh chart's old viewport on save.
    sf('set',chart.Id,'.viewLimits',reshape(c.view_limits,1,[]),'.zoomFactor',c.zoom);
end
restoreLogging(mdl,current.systems,logging);
after=layout_profile(mdl);
assert(isequal(actual,layout_contract(after)),'talkrtl:LayoutConnectivity','Layout changed model connections.');
assert(isequaln(logicBefore,chartLogic(mdl)),'talkrtl:LayoutLogic','Layout changed chart logic.');
info=struct('file',file,'blocks',numel(approved.blocks), ...
    'diagrams',numel(approved.systems),'charts',numel(approved.charts));
fprintf('Applied approved layout: %d blocks, %d diagrams, %d charts.\n',info.blocks,info.diagrams,info.charts);
end
function path=full(mdl,relative)
path=mdl;if ~isempty(relative),path=[mdl '/' relative];end
end
function h=terminal(ports,id)
index=find(strcmp({ports.id},id),1);
assert(~isempty(index),'talkrtl:LayoutPorts','Missing terminal: %s.',id);
h=ports(index).handle;
end
function saved=captureLogging(mdl,systems)
saved=struct('id',{},'properties',{});
props={'Name','DataLogging','DataLoggingNameMode','DataLoggingName', ...
    'DataLoggingDecimateData','DataLoggingDecimation','DataLoggingLimitDataPoints','DataLoggingMaxPoints'};
for s=systems(:)'
    ports=layout_ports(mdl,full(mdl,s.path));
    for p=ports(:)'
        if ~strcmp(p.group,'Outport'),continue;end
        meta=get_param(p.handle,'ObjectParameters');values=struct();
        for prop=props
            if isfield(meta,prop{1}),values.(prop{1})=get_param(p.handle,prop{1});end
        end
        saved(end+1)=struct('id',p.id,'properties',values); %#ok<AGROW>
    end
end
end
function restoreLogging(mdl,systems,saved)
ports=[];
for s=systems(:)',ports=[ports layout_ports(mdl,full(mdl,s.path))];end %#ok<AGROW>
for item=saved(:)'
    h=terminal(ports,item.id);
    for field=fieldnames(item.properties)'
        set_param(h,field{1},item.properties.(field{1}));
    end
end
end
function values=chartLogic(mdl)
values={};
for c=sfroot().find('-isa','Stateflow.Chart')'
    if ~startsWith(c.Path,[mdl '/']),continue;end
    path=c.Path(numel(mdl)+2:end);
    values{end+1}=strjoin({path,c.SampleTime,c.ChartUpdate,c.ActionLanguage, ...
        num2str(c.ExecuteAtInitialization),c.Decomposition},'|'); %#ok<AGROW>
    for s=c.find('-isa','Stateflow.State')'
        values{end+1}=[path '|state|' s.Name '|' s.LabelString]; %#ok<AGROW>
    end
    for t=c.find('-isa','Stateflow.Transition')'
        src='DEFAULT';if ~isempty(t.Source),src=t.Source.Name;end
        values{end+1}=sprintf('%s|%s|%s|%d|%s',path,src,t.Destination.Name,t.ExecutionOrder,t.LabelString); %#ok<AGROW>
    end
end
values=sort(values);
end
