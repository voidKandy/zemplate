# Zemplate
> A minimal, zero-dependency templating engine written in Zig.

`zemplate` leverages Zig’s **comptime** capabilities to build a function graph for efficient template rendering. Templates can access nested fields, run loops, and serialize fields to JSON — all with zero runtime reflection.

Originally created for my [portfolio site](https://github.com/voidKandy/zortfolio), `zemplate` became its own project because the model is flexible and extensible.

---

## Concepts

- **Scope**: Every template has a root scope for its context struct. Loops and conditional blocks create child scopes.  
  - `.` accesses the current scope’s root  
  - `.<field>` accesses a field in the current scope  
- **Statements vs Expressions**:  
  - **Expressions**: `{| <expression> |}` — used for rendering values  
  - **Statements**: `||zz <statement> zz||` — used for loops or control flow  
- **JSON Serialization**: `{| .field json |}` serializes a field to JSON. Whitespace control only applies to JSON output.

---

## Template Syntax Examples
> There are more great usage examples in `tests/rendering.zig` and `tests/all.zig`

### Simple Interpolation

```zig
const MyStruct = struct { field: []const u8 };

var tmpl = try zemplate.Template.init(
    allocator,
    &MyStruct{ .field = "World" },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\ Hello {|.field|}!
, .{});

// Output: "Hello World!"
```

---

### Loops Over Fields

```zig
var tmpl = try zemplate.Template.init(
    allocator,
    &MyStruct{ .field = "World" },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\ ||zz for .field zz||
    \\ {|.|}
    \\ ||zz endfor zz||
, .{});

// Output:
// W
// o
// r
// l
// d
```

---

### Nested Field Access

```zig
const Nested = struct { inner: []const u8 };
const TestStruct = struct { field: Nested };

var tmpl = try zemplate.Template.init(
    allocator,
    &TestStruct{ .field = .{ .inner = "World" } },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\ Hello {|.field.inner|}!
, .{});

// Output: "Hello World!"
```

---

### JSON Serialization

```zig
const Test = struct { field: struct { key: u32 } };

var tmpl = try zemplate.Template.init(
    allocator,
    &Test{ .field = .{ .key = 42 } },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\Hello {| .field json |}!
, .{});


// Output: "Hello {\"key\":42}!"
```

---


## Todos

- [x] Associate templates with any struct, control rendering via struct fields  
- [x] Basic string interpolation  
- [x] JSON rendering  
- [x] For loops  
- [ ] If statements  
- [ ] Performance optimization
