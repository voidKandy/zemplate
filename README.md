# Zemplate
> A minimal, zero-dependency templating engine written in Zig.

`zemplate` leverages Zig’s **comptime** capabilities to build a function graph for efficient template rendering. Templates can access nested fields, iterate over values, evaluate conditionals, and render string literals — all with zero runtime reflection.

Originally created for my [portfolio site](https://github.com/voidKandy/zortfolio), `zemplate` became its own project because the model is flexible and extensible.

---

## Concepts

- **Scope**  
  Every template has a root scope derived from the provided context struct.  
  Loops and conditional blocks create child scopes.
  - Scope is resolved by leading periods:
    - `.` = current scope
    - `..` = parent scope
    - more periods walk upward
  - Appending a field accesses that scope’s field (`..field`)

- **Statements vs Expressions**
  - **Expressions**: `{| <expression> |}`  
    Used to render values into the output.
  - **Statements**: `||zz <statement> zz||`  
    Used for control flow such as loops and conditionals.

- **Truthiness & Optionals**
  - Optional fields (`?T`) may be used directly in `if` statements
  - `null` evaluates as false
  - Booleans behave as expected

- **String Literals & Comparisons**
  - Single-quoted string literals are supported *inside statements* : `'example'`
  - Equality and comparison operators may be used in conditionals

- **JSON Serialization**
  - `{| .field json |}` serializes a field to JSON
  - serialization options are passed to the `render` function

---

## Template Syntax Examples
> More complete examples can be found in `tests/rendering.zig` and `tests/templating.zig`

### Simple Interpolation

```zig
const MyStruct = struct { field: []const u8 };

var tmpl = try zemplate.Template(MyStruct).init(
    allocator,
    .{ .field = "World" },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\ Hello {|.field|}!
, .{});

// Output: "Hello World!"
```

---

### Loops Over Fields

slices and arrays are iterable and will be rendered item-by-item:

```zig
var tmpl = try zemplate.Template(MyStruct).init(
    allocator,
    .{ .field = "World" },
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

### Conditional Rendering

```zig
const Test = struct {
    opt: ?[]const u8,
};

var tmpl = try zemplate.Template(Test).init(
    allocator,
    .{ .opt = "optional" },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\ ||zz if .opt zz||
    \\ {|.|}
    \\ ||zz endif zz||
, .{});

// Output:
// optional
```

---

### Comparisons & String Literals

```zig
const Test = struct {
    value: u32,
    inner: struct { text: []const u8 },
};

var tmpl = try zemplate.Template(Test).init(
    allocator,
    .{ .value = 42, .inner = .{ .text = "inner string" } },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\ ||zz if .value == 42 zz||
    \\ {|.value|} == 42
    \\ ||zz endif zz||
    \\ ||zz if .inner.text == 'inner string' zz||
    \\ {|.inner.text|} == 'inner string'
    \\ ||zz endif zz||
, .{});
```

---

### Nested Field Access

```zig
const Nested = struct { inner: []const u8 };
const TestStruct = struct { field: Nested };

var tmpl = try zemplate.Template(TestStruct).init(
    allocator,
    .{ .field = .{ .inner = "World" } },
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

var tmpl = try zemplate.Template(Test).init(
    allocator,
    .{ .field = .{ .key = 42 } },
);
defer tmpl.deinit();

const render = try tmpl.render(
    \\ Hello {| .field json |}!
, .{});

// Output: "Hello {\"key\":42}!"
```

---

## Todos

- [x] Associate templates with any struct
- [x] Basic string interpolation
- [x] JSON rendering
- [x] For loops
- [x] If statements
- [x] String literals
- [ ] Performance optimization

## Known Issues
Template's cannot have `[][]T` as a direct field. A workaround is to use a custom struct. So instead of: 
```zig
const MyTemplateStruct = struct {
  array_array: [][]const u8,
};
```
Do something like: 
```zig
const StringWrap = struct {
  string: []const u8,
};
const MyTemplateStruct = struct {
  string_wrap_array: []StringWrap,
};
```


