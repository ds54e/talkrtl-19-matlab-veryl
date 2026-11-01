function nets=layout_nets(sys,ports)
% Capture a native line tree as one trunk route plus routes to each branch.
% Only portable terminal names and pixel coordinates leave this function.
nets=struct('kind',{},'root',{},'terminals',{},'paths',{});
lines=find_system(sys,'LookUnderMasks','all','FindAll','on', ...
    'SearchDepth',1,'Type','line');
covered=[];
for h=lines(:)'
    if ismember(h,covered),continue;end
    src=get_param(h,'SrcPortHandle');
    if numel(src)~=1 || src<0 || get_param(h,'LineParent')~=-1,continue;end
    root=find([ports.handle]==src & [ports.line]==h,1);
    if isempty(root),continue;end
    tree=descendants(h);
    assert(isempty(intersect(covered,tree)),'Overlapping native wire trees.');
    covered=[covered tree]; %#ok<AGROW>
    members=find(ismember([ports.line],tree));
    kind='physical';if strcmp(ports(root).group,'Outport'),kind='signal';end
    paths=routes(tree,ports(members),ports(root).id);
    nets(end+1)=struct('kind',kind,'root',ports(root).id, ...
        'terminals',{sort({ports(members).id})},'paths',paths); %#ok<AGROW>
end
assert(isequal(sort(unique(covered(:))),sort(lines(:))), ...
    'talkrtl:LayoutWires','Unsupported or dangling wire in %s.',sys);
if ~isempty(nets)
    keys=arrayfun(@netkey,nets,'UniformOutput',false);
    [~,order]=sort(keys);nets=nets(order);
end
end

function handles=descendants(root)
handles=[];pending=root;
while ~isempty(pending)
    h=pending(1);pending(1)=[];
    if ismember(h,handles),continue;end
    handles(end+1)=h; %#ok<AGROW>
    children=get_param(h,'LineChildren');
    pending=[pending children(:)']; %#ok<AGROW>
end
end

function paths=routes(handles,ports,rootId)
vertices=zeros(0,2);edges=struct('a',{},'b',{},'points',{});
index=containers.Map('KeyType','char','ValueType','double');
for h=handles
    points=double(get_param(h,'Points'));
    a=vertex(points(1,:));b=vertex(points(end,:));
    edges(end+1)=struct('a',a,'b',b,'points',points); %#ok<AGROW>
end
degree=zeros(size(vertices,1),1);
for e=edges
    if e.a~=e.b,degree(e.a)=degree(e.a)+1;degree(e.b)=degree(e.b)+1;end
end
anchors=zeros(1,numel(ports));
for pi=1:numel(ports)
    ei=find(handles==ports(pi).line,1);e=edges(ei);h=handles(ei);
    src=get_param(h,'SrcPortHandle');dst=get_param(h,'DstPortHandle');
    if any(src==ports(pi).handle)
        anchors(pi)=e.a;
    elseif any(dst==ports(pi).handle)
        anchors(pi)=e.b;
    elseif degree(e.a)==1 && degree(e.b)>1
        anchors(pi)=e.a;
    elseif degree(e.b)==1 && degree(e.a)>1
        anchors(pi)=e.b;
    else
        % Stub tips can be 11 pixels away from Port.Position. Pick the end
        % nearest the owning block frame, not nearest the extended port.
        b=get_param(get_param(ports(pi).handle,'Parent'),'Position');
        da=frameDistance(vertices(e.a,:),b);db=frameDistance(vertices(e.b,:),b);
        if da<db,anchors(pi)=e.a;else,anchors(pi)=e.b;end
    end
end
ri=find(strcmp({ports.id},rootId),1);root=anchors(ri);
previous=zeros(size(degree));via=zeros(size(degree));previous(root)=-1;
queue=root;head=1;
while head<=numel(queue)
    current=queue(head);head=head+1;
    for ei=1:numel(edges)
        e=edges(ei);next=0;
        if e.a==current,next=e.b;elseif e.b==current,next=e.a;end
        if next && previous(next)==0
            previous(next)=current;via(next)=ei;queue(end+1)=next; %#ok<AGROW>
        end
    end
end
sequences=cell(1,numel(ports));lengths=zeros(1,numel(ports));
for pi=1:numel(ports)
    v=anchors(pi);sequence=[];
    while v~=root
        assert(previous(v)>0,'talkrtl:LayoutWires','Unreachable terminal %s.',ports(pi).id);
        sequence=[via(v) sequence];v=previous(v); %#ok<AGROW>
    end
    sequences{pi}=sequence;
    for ei=sequence,lengths(pi)=lengths(pi)+sum(abs(diff(edges(ei).points)), 'all');end
end
targets=setdiff(1:numel(ports),ri,'stable');
assert(~isempty(targets),'Wire has no destination.');
[~,furthest]=max(lengths(targets));first=targets(furthest);
targets=[first targets(targets~=first)];
placed=false(1,numel(edges));paths=struct('from_port',{},'to_port',{},'points',{});
for pi=targets
    sequence=sequences{pi};start=root;cut=1;
    if ~isempty(paths)
        while cut<=numel(sequence) && placed(sequence(cut))
            start=other(edges(sequence(cut)),start);cut=cut+1;
        end
    end
    points=vertices(start,:);cursor=start;
    for ei=sequence(cut:end)
        e=edges(ei);part=e.points;
        if cursor==e.b,part=flipud(part);end
        points=[points;part(2:end,:)];cursor=other(e,cursor);placed(ei)=true; %#ok<AGROW>
    end
    if size(points,1)==1,points=[points;points];end
    from='';if isempty(paths),from=rootId;end
    paths(end+1)=struct('from_port',from,'to_port',ports(pi).id,'points',points); %#ok<AGROW>
end
    function i=vertex(point)
        key=sprintf('%.17g,%.17g',point);
        if isKey(index,key),i=index(key);
        else,i=size(vertices,1)+1;vertices(i,:)=point;index(key)=i;end
    end
end

function v=other(e,current)
if e.a==current,v=e.b;else,v=e.a;end
end
function d=frameDistance(p,r)
dx=max([r(1)-p(1),0,p(1)-r(3)]);
dy=max([r(2)-p(2),0,p(2)-r(4)]);d=dx*dx+dy*dy;
end
function key=netkey(net)
key=[net.kind '|' strjoin(net.terminals,'|')];
if strcmp(net.kind,'signal'),key=[net.root '|' key];end
end
