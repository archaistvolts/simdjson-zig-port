:warning: **Work in progress.  Expect bugs and/or missing features** :warning:

# simdjzon
This is a port of [simdjson](https://github.com/simdjson/simdjson), a high performance JSON parser developed by Daniel Lemire and Geoff Langdale to [zig](https://ziglang.org/).  

# cpu support
Only 64 bit CPUs are supported so far.

#### x86_64
A CPU with AVX is required and CLMUL is preferred. the following usually have
both
* Intel - Haswell from 2013 onwards
* AMD - Ryzen/EPYC CPU (Q1 2017)

These commands show how to test for specific target and cpu support
```console
zig build test -Dtarget=x86_64-linux -Dcpu=x86_64+avx # uses clmulSoft - missing pclmul
zig build test -Dtarget=x86_64-linux -Dcpu=x86_64+avx+pclmul
# zig build test -Dtarget=x86_64-linux # doesn't work - missing avx
# zig build test -Dcpu=x86_64_v2 # doesn't work - missing avx
```

#### aarch64
A CPU with AES is preferred.
```console
zig build test -Dtarget=aarch64-linux -Dcpu=apple_latest-aes -fqemu # uses clmulSoft
zig build test -Dtarget=aarch64-linux -fqemu
```

#### powerpc
Not supported yet
```console
# zig build test -Dtarget=powerpc-linux -fqemu # doesn't work - no classify() + 32bit errors
# zig build test -Dtarget=powerpc64-linux -fqemu # doesn't work - no classify()
```

#### fallback
No fallback for unsupported CPUs is provided yet.

```console
# zig build test -Dcpu=baseline # doesn't work - no classify()
```

# zig compiler support
The main branch is meant to compile with zig's master branch.  It is tested weekly on linux, windows and macos. 

For older compiler versions, use a [tagged version](https://github.com/travisstaloch/simdjzon/tags).

# usage
### Git Clone
```console
# json validation
$ git clone https://github.com/travisstaloch/simdjzon
$ cd simdjzon
$ zig build -Drelease-fast # uses the dom api by default
$ zig-out/bin/simdjzon test/test.json
$ echo $? # 0 on success
0
$ zig build -Drelease-fast -Dondemand # use the ondemand api
$ zig-out/bin/simdjzon test/test.json
$ echo $? # 0 on success
0
$ zig build test
All 19 tests passed.
```

### Zig Package
```console
$ $ zig fetch --save git+https://github.com/travisstaloch/simdjzon
info: resolved to commit 28d46c979f761b211539232378138b692ef50d55
```
```zig
// build.zig
const simdjzon_dep = b.dependency("simdjzon", .{ .target = target, .optimize = optimize });
const exe_mod = b.createModule(.{
    // ...
    .imports = &.{
        .{ .name = "simdjzon", .module = simdjzon_dep.module("simdjzon") },
    },
});
```
```zig
// main.zig
const simdjzon = @import("simdjzon");
```
#### dom API
```zig
// const dom = @import("simdjzon").dom;
test "get with struct - readme" {
    const S = struct { a: u8, b: []const u8, c: struct { d: u8 } };
    const input =
        \\{"a": 42, "b": "b-string", "c": {"d": 126}}
    ;
    var parser = try dom.Parser.initFixedBuffer(testing.allocator, input, .{});
    defer parser.deinit();
    try parser.parse();
    var s: S = undefined;
    try parser.element().get(&s);
    try testing.expectEqual(@as(u8, 42), s.a);
    try testing.expectEqualStrings("b-string", s.b);
    try testing.expectEqual(@as(u8, 126), s.c.d);
}

test "at_pointer - readme" {
    const input =
        \\{"a": {"b": [1,2,3]}}
    ;
    var parser = try dom.Parser.initFixedBuffer(testing.allocator, input, .{});
    defer parser.deinit();
    try parser.parse();
    const b0 = try parser.element().at_pointer("/a/b/0");
    try testing.expectEqual(@as(i64, 1), try b0.get_int64());
}
```
#### ondemand API
:warning: ondemand get_string() seems to have bugs when building in release small modes. :warning:
```zig
// const ondemand = @import("simdjzon").ondemand;
// ondemand api users must specify `pub const read_buf_cap = N;` in their
// root source file.  In tests, this defaults to `std.mem.page_size`.
test "ondemand get with struct - readme" {
    const S = struct { a: struct { b: []const u8 } };
    const input =
        \\{"a": {"b": "b-string"}}
    ;
    const file_name = "ondemand_get_with_struct_readme";
    var tdir = testing.tmpDir(.{});
    defer tdir.cleanup();
    { // write file
        const tfile = try tdir.dir.createFile(io, file_name, .{});
        defer tfile.close(io);
        try tfile.writePositionalAll(io, input, 0);
    }
    // note: ondemand api requires a seekable file.
    const tfile = try tdir.dir.openFile(io, file_name, .{});
    var read_buf: [READ_BUF_CAP]u8 = undefined;
    var src = tfile.reader(testing.io, &read_buf);
    var parser = try ondemand.Parser.init(&src, testing.allocator, file_name, .{});
    defer parser.deinit();
    var doc = try parser.iterate();

    var s: S = undefined;
    try doc.get(&s, .{ .allocator = testing.allocator });
    defer testing.allocator.free(s.a.b);
    try testing.expectEqualStrings("b-string", s.a.b);
}


    const input =
        \\{"a": {"b": [1,2,3]}}
    ;
    // ondemand api requires a seekable file.
    const file_name = "ondemand_at_pointer_readme";
    var tdir = testing.tmpDir(.{});
    defer tdir.cleanup();
    { // write file
        const tfile = try tdir.dir.createFile(io, file_name, .{});
        defer tfile.close(io);
        try tfile.writePositionalAll(io, input, 0);
    }
    const tfile = try tdir.dir.openFile(io, file_name, .{});
    var read_buf: [READ_BUF_CAP]u8 = undefined;
    var src = tfile.reader(testing.io, &read_buf);
    var parser = try ondemand.Parser.init(&src, testing.allocator, file_name, .{});
    defer parser.deinit();
    var doc = try parser.iterate();
    var b0 = try doc.at_pointer("/a/b/0");
    try testing.expectEqual(@as(u8, 1), try b0.get_int(u8));
}
```

# performance
## parsing/validating twitter.json (630Kb)
### simdjson

### benchmark vs simdjson - 5/7/26
```console
$ cd zig-out/bin/
$ wget https://raw.githubusercontent.com/simdjson/simdjson/master/singleheader/simdjson.h https://raw.githubus
ercontent.com/simdjson/simdjson/master/singleheader/simdjson.cpp https://raw.githubusercontent.com/simdjson/simdjson/master/jsonexampl
es/twitter.json
# ...

$ cat > main.cpp
#include "simdjson.h"
using namespace simdjson;
int main(int argc, char** argv) {
    if(argc != 2) {
        std::cout << "USAGE: ./simdjson <file.json>" << std::endl;
        exit(1);
    }
    dom::parser parser;
    try
    {
        const dom::element doc = parser.load(argv[1]);
    }
    catch(const std::exception& e)
    {
        std::cerr << e.what() << '\n';
        return 1;
    }
    return 0;
}
$ g++ --version
g++ (GCC) 15.2.1 20260123 (Red Hat 15.2.1-7)
$ g++ main.cpp simdjson.cpp -o simdjson -O3 -march=native
$ cd ../..
$ poop 'zig-out/bin/simdjson zig-out/bin/twitter.json' 'zig-out/bin/simdjzon zig-out/bin/twitter.json'
Benchmark 1 (2054 runs): zig-out/bin/simdjson zig-out/bin/twitter.json
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          2.39ms ±  184us    1.86ms … 4.15ms         72 ( 4%)        0%
  peak_rss           5.22MB ±  101KB    4.85MB … 5.58MB        300 (15%)        0%
  cpu_cycles         2.39M  ± 89.1K     2.26M  … 3.39M         153 ( 7%)        0%
  instructions       5.28M  ± 4.24      5.28M  … 5.28M          83 ( 4%)        0%
  cache_references    154K  ± 2.77K      150K  …  192K         107 ( 5%)        0%
  cache_misses       24.1K  ± 1.38K     20.8K  … 32.1K          50 ( 2%)        0%
  branch_misses      21.5K  ±  647      19.0K  … 23.7K           4 ( 0%)        0%
Benchmark 2 (2355 runs): zig-out/bin/simdjzon zig-out/bin/twitter.json
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          2.08ms ±  160us    1.67ms … 3.17ms         46 ( 2%)        ⚡- 12.9% ±  0.4%
  peak_rss           2.35MB ± 72.3KB    1.97MB … 2.39MB          2 ( 0%)        ⚡- 55.0% ±  0.1%
  cpu_cycles         1.97M  ± 69.1K     1.88M  … 2.83M         139 ( 6%)        ⚡- 17.5% ±  0.2%
  instructions       5.37M  ± 2.57      5.37M  … 5.37M          92 ( 4%)        💩+  1.7% ±  0.0%
  cache_references   98.9K  ± 2.69K     95.0K  …  148K          21 ( 1%)        ⚡- 35.8% ±  0.1%
  cache_misses       5.52K  ± 1.72K     2.43K  … 11.1K           4 ( 0%)        ⚡- 77.1% ±  0.4%
  branch_misses      7.02K  ±  692      5.11K  … 9.10K           1 ( 0%)        ⚡- 67.4% ±  0.2%
```

### timed against simdjson, go, nim, zig std lib
The simdjson binary was compiled as shown above.  Go and nim binaries created with sources from JSONTestSuite. [zig std lib driver](bench/src/zig_json.zig).
Validation times for several large json files.  Created with [benchmark_and_plot.jl](bench/benchmark_and_plot.jl)

![results](https://github.com/travisstaloch/simdjson-zig/blob/media/bench/validation_grouped.png)

# JSONTestSuite

Results of running simdjson and simdjzon through [JSONTestSuite](https://github.com/nst/JSONTestSuite).  Results are equal as of 8/7/21

![results](https://github.com/travisstaloch/simdjson-zig/blob/media/JSONTestSuiteResults.png)
