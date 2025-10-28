# Contributing to [Project Name]

Thank you for your interest in contributing! This document provides guidelines and workflows for contributing to this Zig project.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [Release Process](#release-process)

---

## Code of Conduct

**Be respectful, constructive, and professional.**

We're building a welcoming community. Please:

- ✅ Provide constructive feedback
- ✅ Help others learn
- ✅ Assume good intentions
- ❌ No harassment, discrimination, or personal attacks

---

## Getting Started

### Prerequisites

- **Zig**: 0.15.0 or later ([installation guide](https://ziglang.org/download/))
- **Git**: For version control
- **Editor**: Any editor with Zig support (VS Code + Zig extension recommended)

### Clone and Build

```bash
# Clone the repository
git clone https://github.com/[username]/[project].git
cd [project]

# Build the project
zig build

# Run tests
zig build test

# Run in debug mode
zig build run
```

### Project Structure

```
project/
├── src/               # Source code
│   ├── main.zig      # Entry point
│   ├── [modules]/    # Feature modules
│   └── test/         # Test files
├── docs/              # Documentation
├── build.zig          # Build configuration
└── README.md          # User documentation
```

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed structure.

---

## Development Workflow

### 1. Create an Issue

**Before starting work**, create or claim an issue:

1. Check existing issues to avoid duplicates
2. Create a new issue describing:
   - **Problem**: What needs to be fixed/added
   - **Solution**: Proposed approach (if any)
   - **Impact**: Who benefits from this change
3. Wait for maintainer feedback/approval for large changes

### 2. Create a Branch

```bash
# Create feature branch
git checkout -b feature/short-description

# Or bugfix branch
git checkout -b fix/issue-number-description
```

**Branch Naming**:

- `feature/[name]`: New features
- `fix/[issue]-[name]`: Bug fixes
- `docs/[name]`: Documentation only
- `refactor/[name]`: Code refactoring
- `test/[name]`: Test additions/improvements

### 3. Make Changes

**Small, focused commits**:

```bash
# Stage changes
git add [files]

# Commit with descriptive message
git commit -m "Add feature X to handle Y

- Implement core functionality
- Add unit tests
- Update documentation

Closes #[issue-number]"
```

### 4. Test Your Changes

```bash
# Run all tests
zig build test

# Format code
zig fmt src/

# Check for common issues
zig build check  # (if available)
```

### 5. Push and Create PR

```bash
# Push to your fork
git push origin feature/short-description

# Create Pull Request on GitHub
# Fill out the PR template
```

---

## Coding Standards

### Tiger Style Principles

We follow **Tiger Style** methodology for safety and reliability:

#### 1. Safety First

**Assertions** (2+ per function):

```zig
pub fn processData(data: []const u8, count: u32) !Result {
    // Pre-conditions
    assert(data.len > 0);
    assert(count <= data.len);

    // ... implementation ...

    // Post-conditions
    assert(result.isValid());
    return result;
}
```

**Bounded Loops** (no infinite loops):

```zig
// ✅ GOOD: Bounded loop
var i: usize = 0;
while (i < items.len and i < MAX_ITERATIONS) : (i += 1) {
    // ... process item ...
}

// ❌ BAD: Unbounded loop
while (condition) {  // What if condition never becomes false?
    // ...
}
```

**Explicit Types** (no `usize` unless necessary):

```zig
// ✅ GOOD: Explicit types
const row_count: u32 = 1000;
const column_index: u32 = 5;

// ❌ BAD: Architecture-dependent
const count: usize = 1000;  // Changes between 32/64 bit
```

#### 2. Error Handling

**Always handle errors explicitly**:

```zig
// ✅ GOOD: Propagate error
const result = try riskyOperation();

// ✅ GOOD: Handle specific error
const result = riskyOperation() catch |err| {
    log.err("Operation failed: {}", .{err});
    return error.OperationFailed;
};

// ⚠️ USE SPARINGLY: Only with proof
const result = riskyOperation() catch unreachable;

// ❌ BAD: Silent failure
const result = riskyOperation() catch null;
```

#### 3. Memory Management

**Explicit allocators**:

```zig
// ✅ GOOD: Caller provides allocator
pub fn create(allocator: Allocator, size: usize) !*MyType {
    const ptr = try allocator.create(MyType);
    // ... initialize ...
    return ptr;
}

// ✅ GOOD: Arena for batch operations
pub fn processBatch(allocator: Allocator, items: []Item) !Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // All temporary allocations freed at once
    // ...
}
```

**Memory ownership**:

- **Document ownership** in function comments
- **Caller-allocated** when possible (less allocations)
- **Free what you allocate** (use `defer`)

#### 4. Code Organization

**Function Size** (≤70 lines):

```zig
// If a function exceeds 70 lines, break it into smaller functions
pub fn complexOperation(data: []const u8) !Result {
    const validated = try validateInput(data);
    const processed = try processData(validated);
    return finalizeResult(processed);
}

fn validateInput(data: []const u8) !ValidatedData { /* ... */ }
fn processData(validated: ValidatedData) !ProcessedData { /* ... */ }
fn finalizeResult(processed: ProcessedData) Result { /* ... */ }
```

**Naming Conventions**:

```zig
// Types: PascalCase
const MyStruct = struct { /* ... */ };

// Functions: camelCase
pub fn doSomething() void { /* ... */ }

// Constants: SCREAMING_SNAKE_CASE
const MAX_SIZE: usize = 1024;

// Variables: snake_case
var item_count: u32 = 0;
```

### Code Style

**Follow Zig conventions**:

```zig
// ✅ GOOD: Zig idioms
const items = std.ArrayList(Item).init(allocator);
defer items.deinit();

for (items.items) |item| {
    // ... process item ...
}

// ✅ GOOD: Explicit null handling
const maybe_value = findItem(id);
if (maybe_value) |value| {
    // Use value
} else {
    // Handle not found
}
```

**Run `zig fmt` before committing**:

```bash
zig fmt src/
```

### Documentation

**Document all public APIs**:

```zig
/// Processes the input data and returns a result.
///
/// Allocates memory using the provided allocator. Caller owns the returned
/// result and must call `result.deinit()` when done.
///
/// Returns error.InvalidInput if data is malformed.
/// Returns error.OutOfMemory if allocation fails.
pub fn processData(allocator: Allocator, data: []const u8) !Result {
    // ...
}
```

**Explain WHY, not WHAT**:

```zig
// ✅ GOOD: Explains reasoning
// Use arena allocator because we make many small temporary allocations
// that can all be freed at once, reducing overhead
var arena = std.heap.ArenaAllocator.init(allocator);

// ❌ BAD: States the obvious
// Create an arena allocator
var arena = std.heap.ArenaAllocator.init(allocator);
```

---

## Testing Requirements

### Test Coverage

**Every PR must include tests**:

- New features: Unit tests + integration tests
- Bug fixes: Test that reproduces the bug
- Refactoring: Existing tests must pass

**Target**: >80% code coverage

### Test Organization

```
src/test/
├── unit/              # Unit tests (mirror src/ structure)
│   ├── [module]/     # Tests for src/[module]/
│   └── ...
├── integration/       # Integration tests
└── benchmark/         # Performance tests
```

### Writing Tests

**Unit Test Template**:

```zig
const std = @import("std");
const testing = std.testing;
const MyModule = @import("../../[module]/core.zig");

test "MyModule: feature description" {
    const allocator = testing.allocator;

    // Setup
    const input = // ...

    // Execute
    const result = try MyModule.doSomething(allocator, input);
    defer result.deinit();

    // Assert
    try testing.expectEqual(expected_value, result.value);
    try testing.expect(result.isValid());
}
```

**Memory Leak Detection**:

```zig
test "MyModule: no memory leaks" {
    const allocator = testing.allocator;

    // Run operation 1000 times
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const result = try MyModule.create(allocator);
        defer result.deinit();
        // ... use result ...
    }

    // testing.allocator will fail if there are leaks
}
```

### Running Tests

```bash
# Run all tests
zig build test

# Run specific test file
zig build test -Dtest-filter="MyModule"

# Run with verbose output
zig build test --summary all
```

---

## Pull Request Process

### PR Checklist

Before submitting a PR, ensure:

- [ ] Code follows Tiger Style guidelines
- [ ] All tests pass (`zig build test`)
- [ ] Code is formatted (`zig fmt src/`)
- [ ] No compiler warnings
- [ ] Documentation updated (if API changed)
- [ ] Commit messages are descriptive
- [ ] PR description explains changes

### PR Template

```markdown
## Description

Brief description of what this PR does.

## Motivation

Why is this change needed? What problem does it solve?

## Changes

- Change 1
- Change 2

## Testing

How was this tested?

- [ ] Unit tests added
- [ ] Integration tests added
- [ ] Manual testing performed

## Checklist

- [ ] Tests pass
- [ ] Code formatted
- [ ] Documentation updated
- [ ] No breaking changes (or documented)

Closes #[issue-number]
```

### Review Process

1. **Automated Checks**: CI runs tests, linting, formatting
2. **Code Review**: Maintainer(s) review code
3. **Feedback**: Address reviewer comments
4. **Approval**: PR approved by maintainer(s)
5. **Merge**: Maintainer merges to main

**Response Time**: Maintainers aim to respond within 3-5 business days.

---

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Incompatible API changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

Example: `1.2.3` = Major.Minor.Patch

### Release Checklist

1. Update version in `build.zig`
2. Update `CHANGELOG.md`
3. Run full test suite
4. Create git tag: `git tag v1.2.3`
5. Push tag: `git push origin v1.2.3`
6. Create GitHub release with notes

---

## Getting Help

### Resources

- **Documentation**: [README.md](../README.md), [ARCHITECTURE.md](./ARCHITECTURE.md)
- **Issues**: [GitHub Issues](https://github.com/[username]/[project]/issues)
- **Discussions**: [GitHub Discussions](https://github.com/[username]/[project]/discussions)

### Questions?

- **General questions**: Open a Discussion
- **Bug reports**: Open an Issue
- **Feature requests**: Open an Issue
- **Security issues**: Email [security@example.com]

---

## Recognition

**Contributors are recognized in**:

- `CHANGELOG.md` for each release
- GitHub Contributors page
- Special thanks in release notes

Thank you for contributing! 🎉

---

## Template Instructions

**Remove this section after customizing:**

1. Replace all `[placeholders]` with actual values
2. Update email addresses for security reports
3. Customize branch naming conventions if needed
4. Add project-specific testing requirements
5. Update CI/CD pipeline details
6. Add Discord/Slack/community links if available
