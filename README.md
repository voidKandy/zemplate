# zemplate
> A very basic, zero-dependency templating engine written in Zig.

I originally wrote this for my [portfolio site](https://github.com/voidKandy/zortfolio), but had a good time doing it so I turned it into its own project.

It currently supports basic interpolation — inserting values from a context struct into a template. Eventually, I’d like to add simple control flow (loops, conditionals), but the goal is to keep it small and simple. Improvements such as these will be implemented as I find I need them for my portfolio.

---

## Example Usage

```zig
const std = @import("std");
const allocator = std.testing.allocator;

const MyContext = struct { field: []const u8 };
const MyTemplate = zemplate.Template(MyContext,
    \\Hello ||zz .field zz||!
);
var tmplt = MyTemplate.init(MyContext{ .field = "World" }, allocator);
var render = try tmplt.render();
defer render.deinit(allocator);

std.debug.print("{s}", .{ render.items });
```
The output would be: "Hello World!"

## Notes

* `render()` returns an `ArrayList(u8)` — you own it, so call `deinit()`.
* Fields that you would like to render in your template from your context type must be `[]const u8`, `[]u8`, or `ArrayList(u8)`.
* Templates copy field data during rendering, so the template does not take ownership of your context.
* For owned fields (`[]u8` or `ArrayList(u8)`), implement a deinit method on your context.
