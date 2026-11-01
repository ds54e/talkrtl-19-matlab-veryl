function profile=layout_profile(mdl)
% Read appearance only. Runtime handles and functional parameters are excluded.
assert(bdIsLoaded(mdl),'Model must be loaded.');
profile=struct('schema_version',1,'matlab_release',version('-release'), ...
    'blocks',struct([]),'systems',struct([]),'charts',struct([]));
charts=sfroot().find('-isa','Stateflow.Chart');
charts=charts(arrayfun(@(c)startsWith(c.Path,[mdl '/']),charts));
chartPaths=arrayfun(@(c)c.Path,charts,'UniformOutput',false);
pending={mdl};
fields={'Position','Orientation','BlockMirror','BlockRotation','NamePlacement','ShowName', ...
    'FontName','FontSize','FontWeight','FontAngle','ForegroundColor', ...
    'BackgroundColor','DropShadow','IconShape'};
while ~isempty(pending)
    sys=pending{1};pending(1)=[];
    blocks=find_system(sys,'LookUnderMasks','all','FollowLinks','off', ...
        'SearchDepth',1,'Type','block');
    blocks(strcmp(blocks,sys))=[];blocks=sort(blocks);
    ports=layout_ports(mdl,sys);
    for bi=1:numel(blocks)
        block=blocks{bi};path=relative(block,mdl);
        meta=get_param(block,'ObjectParameters');graphics=struct();
        for field=fields
            if isfield(meta,field{1}) || ismember(field{1},{'BlockMirror','BlockRotation'})
                graphics.(field{1})=get_param(block,field{1});
            end
        end
        side='';if strcmp(get_param(block,'BlockType'),'PMIOPort'),side=get_param(block,'Side');end
        item=struct('path',path,'type',get_param(block,'BlockType'), ...
            'ports',{sort({ports(strcmp({ports.block},path)).id})}, ...
            'graphics',graphics,'port_side',side);
        profile.blocks=[profile.blocks item]; %#ok<AGROW>
        if strcmp(item.type,'SubSystem') && isempty(get_param(block,'ReferenceBlock')) ...
                && ~ismember(block,chartPaths)
            pending{end+1}=block; %#ok<AGROW>
        end
    end
    notes=struct('text',{},'position',{});
    handles=find_system(sys,'FindAll','on','SearchDepth',1,'Type','annotation');
    for h=handles(:)'
        obj=get_param(h,'Object');
        notes(end+1)=struct('text',char(obj.Text),'position',obj.Position); %#ok<AGROW>
    end
    system=struct('path',relative(sys,mdl),'zoom',get_param(sys,'ZoomFactor'), ...
        'nets',layout_nets(sys,ports),'annotations',notes);
    profile.systems=[profile.systems system]; %#ok<AGROW>
end
for c=charts(:)'
    states=struct('name',{},'position',{},'font_size',{});
    for s=c.find('-isa','Stateflow.State')'
        states(end+1)=struct('name',s.Name,'position',s.Position,'font_size',s.FontSize); %#ok<AGROW>
    end
    if ~isempty(states),[~,order]=sort({states.name});states=states(order);end
    transitions=struct('source',{},'destination',{},'order',{},'source_clock',{}, ...
        'destination_clock',{},'source_endpoint',{},'midpoint',{}, ...
        'label_position',{},'font_size',{},'arrow_size',{});
    for t=c.find('-isa','Stateflow.Transition')'
        src='DEFAULT';endpoint=[];
        if isempty(t.Source),endpoint=t.SourceEndpoint;else,src=t.Source.Name;end
        transitions(end+1)=struct('source',src,'destination',t.Destination.Name, ...
            'order',t.ExecutionOrder,'source_clock',t.SourceOClock, ...
            'destination_clock',t.DestinationOClock,'source_endpoint',endpoint, ...
            'midpoint',t.MidPoint,'label_position',t.LabelPosition(1:2), ...
            'font_size',t.FontSize,'arrow_size',t.ArrowSize); %#ok<AGROW>
    end
    if ~isempty(transitions)
        keys=arrayfun(@(t)sprintf('%s|%s|%d',t.source,t.destination,t.order), ...
            transitions,'UniformOutput',false);
        [~,order]=sort(keys);transitions=transitions(order);
    end
    item=struct('path',relative(c.Path,mdl),'zoom',sf('get',c.Id,'.zoomFactor'), ...
        'view_limits',sf('get',c.Id,'.viewLimits'), ...
        'states',states,'transitions',transitions);
    profile.charts=[profile.charts item]; %#ok<AGROW>
end
if ~isempty(profile.blocks),[~,i]=sort({profile.blocks.path});profile.blocks=profile.blocks(i);end
if ~isempty(profile.systems),[~,i]=sort({profile.systems.path});profile.systems=profile.systems(i);end
if ~isempty(profile.charts),[~,i]=sort({profile.charts.path});profile.charts=profile.charts(i);end
end
function path=relative(path,mdl)
if strcmp(path,mdl),path='';else,path=path(numel(mdl)+2:end);end
end
