function schema = layout_schema()
% Display-only fields shared by profile capture and application.
schema.version = 1;
schema.graphics = {'Position','Orientation','BlockMirror','BlockRotation', ...
    'NamePlacement','ShowName','FontName','FontSize','FontWeight','FontAngle', ...
    'ForegroundColor','BackgroundColor','DropShadow','IconShape'};
% These native properties are readable but absent from ObjectParameters.
schema.native_graphics = {'BlockMirror','BlockRotation'};
end
