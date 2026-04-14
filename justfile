set dotenv-load

export PERL5LIB := env("HOME") + "/perl5/lib/perl5:" + justfile_directory() + "/lib"
export PATH := env("HOME") + "/perl5/bin:" + env("PATH")

# Run all tests
test:
    prove -I lib t/

# Run conformance tests
conformance:
    uv run --with 'hegel-core==0.4.1' --with pytest --with hypothesis --with pytest-subtests \
        pytest conformance/tests/test_conformance.py -v

# Run tests with coverage
coverage:
    PERL5OPT="-MDevel::Cover=-db,cover_db,-ignore,t/,-ignore,conformance/" prove -I lib t/
    cover -report text cover_db

# Check coverage meets requirements
check-coverage: coverage
    @perl -e ' \
        open my $fh, "<", "cover_db/coverage.json" or die "Run coverage first"; \
        # For now, just verify the report was generated \
        print "Coverage report generated.\n"; \
    '

# All CI checks
check: test conformance

# Clean build artifacts
clean:
    rm -rf cover_db .hegel .hypothesis .pytest_cache
