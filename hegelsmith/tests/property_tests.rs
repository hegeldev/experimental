use hegel::TestCase;
use hegel::generators;
use hegelsmith::gen_expr::gen_expr_for_type;
use hegelsmith::program::render_program;
use hegelsmith::statements::{Env, Statement, generate_statements};
use hegelsmith::types::{gen_hashable_type, gen_type};

#[hegel::test]
fn generated_types_render_without_panic(tc: TestCase) {
    let rt = gen_type(&tc, 2);
    let rendered = rt.render();
    assert!(!rendered.is_empty());
}

#[hegel::test]
fn hashable_types_are_hashable(tc: TestCase) {
    let rt = gen_hashable_type(&tc, 2);
    assert!(
        rt.is_hashable(),
        "gen_hashable_type produced non-hashable type: {:?}",
        rt
    );
}

#[hegel::test]
fn hashable_types_are_eq(tc: TestCase) {
    let rt = gen_hashable_type(&tc, 2);
    assert!(rt.is_eq(), "hashable type should be eq: {:?}", rt);
}

#[hegel::test]
fn gen_expr_output_type_matches_requested_type(tc: TestCase) {
    let rt = gen_type(&tc, 1);
    let expr = gen_expr_for_type(&tc, &rt, 1);
    assert_eq!(
        expr.output_type(),
        rt,
        "gen_expr_for_type({:?}) produced expr with output_type {:?}",
        rt,
        expr.output_type()
    );
}

#[hegel::test]
fn gen_expr_renders_without_panic(tc: TestCase) {
    let rt = gen_type(&tc, 1);
    let expr = gen_expr_for_type(&tc, &rt, 1);
    let rendered = expr.render();
    assert!(!rendered.is_empty());
}

#[hegel::test]
fn generated_statements_are_nonempty(tc: TestCase) {
    let stmts = generate_statements(&tc);
    assert!(!stmts.is_empty(), "generate_statements produced empty list");
}

#[hegel::test]
fn generated_statements_contain_at_least_one_assertion(tc: TestCase) {
    let stmts = generate_statements(&tc);
    let has_assert = stmts
        .iter()
        .any(|s| matches!(s, Statement::Assert { .. } | Statement::AssertEq { .. }));
    assert!(
        has_assert,
        "generated statements should contain at least one assertion"
    );
}

#[hegel::test]
fn generated_statements_all_render(tc: TestCase) {
    let stmts = generate_statements(&tc);
    for stmt in &stmts {
        let rendered = stmt.render();
        assert!(!rendered.is_empty());
    }
}

#[hegel::test]
fn generated_program_has_valid_structure(tc: TestCase) {
    let stmts = generate_statements(&tc);
    let program = render_program(&stmts);

    assert!(program.contains("use hegel::TestCase;"));
    assert!(program.contains("fn main()"));
    assert!(program.contains("Hegel::new("));
    assert!(program.contains(".run();"));

    // Check balanced braces
    let opens: usize = program.chars().filter(|c| *c == '{').count();
    let closes: usize = program.chars().filter(|c| *c == '}').count();
    assert_eq!(opens, closes, "unbalanced braces in generated program");
}

#[hegel::test]
fn type_predicates_are_consistent(tc: TestCase) {
    let rt = gen_type(&tc, 2);

    // Integers should be hashable and eq
    if rt.is_integer() {
        assert!(rt.is_hashable());
        assert!(rt.is_eq());
        assert!(rt.is_ord());
    }

    // Floats should not be hashable, eq, or ord
    if rt.is_float() {
        assert!(!rt.is_hashable());
        assert!(!rt.is_eq());
        assert!(!rt.is_ord());
    }

    // Collections are not hashable
    if rt.is_collection() {
        assert!(!rt.is_hashable());
    }
}

#[hegel::test]
fn env_fresh_vars_are_unique(tc: TestCase) {
    let mut env = Env::new();
    let n: usize = tc.draw(generators::integers::<usize>().min_value(1).max_value(50));
    let mut names = std::collections::HashSet::new();
    for _ in 0..n {
        let name = env.fresh_var();
        assert!(names.insert(name.clone()), "duplicate var name: {}", name);
    }
}
