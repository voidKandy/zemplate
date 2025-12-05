# zemplate
> A very basic, zero-dependency templating engine written in Zig.

I originally wrote this for my [portfolio site](https://github.com/voidKandy/zortfolio), but had a good time doing it so I turned it into its own project.

It currently supports basic interpolation — inserting values from a context struct into a template. Eventually, I’d like to add simple control flow (loops, conditionals), but the goal is to keep it small and simple. Improvements such as these will be implemented as I find I need them for my portfolio.

---

## Example Usage

```zig
const std = @import("std");
const allocator = std.testing.allocator;
const TestTmpl = zemplate.Template(struct { field: []const u8 });
var tmpl = TestTmpl.init(.{ .field = "World" });

const render = try tmpl.render(allocator,
    \\ Hello ||zz .field zz||!
, .{});

defer allocator.free(render);
std.debug.print("{s}", .{ render.items });
```
The output would be: "Hello World!"

### Json Serialization
There is also support for serializing fields as JSON, this is a newer feature and may have some bugs.
```zig
const std = @import("std");
const allocator = std.testing.allocator;
const TestTmpl = zemplate.Template(struct { field: struct{key: u32} });
var tmpl = TestTmpl.init(.{ .field = .{ .key = 42 } });
const render = try tmpl.render(
    allocator,
    \\Hello ||zz .field json zz||!
, .{});
defer allocator.free(render);

std.debug.print("{s}", .{ render });
```
The output would be: "Hello { "key": 42 }!"


## Notes

* Fields that you would like to render in your template from your context type must be `[]const u8`, `[]u8`, or `ArrayList(u8)`, otherwise the keyword `json` must be used in order to render the field.
* For owned fields (`[]u8` or `ArrayList(u8)`), implement a deinit method on your context.

## Todos
- [x]Associate templates with any struct, control template rendering via struct fields
- [x]Basic string interpolation
- [x]Json Rendering
- [x]For loops
- [ ]If statements
- [ ]Template Context method access
- [ ]Optimization
