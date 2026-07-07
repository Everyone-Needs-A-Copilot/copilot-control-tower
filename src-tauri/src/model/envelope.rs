//! `schema_version` type + the bidirectional range-gate (T3, Decision D-5).
//!
//! Parses `schema_version` ("MAJOR.MINOR[.PATCH]") into a comparable tuple
//! and checks `MIN_SCHEMA <= v < MAX_SCHEMA_EXCLUSIVE`. An older schema is as
//! fatal as a newer one — this is an explicit contract invariant
//! (`docs/01-architecture/cli-contract.md`), not defensive padding.
//! Out-of-range => the app-owned `CliUnreadable` state, never a partial
//! parse.
//!
//! Mirrors `docs/01-architecture/schemas/_envelope.schema.json`'s
//! `schema_version` `$def`.

/// Inclusive lower bound (Decision D-5). Pinned at `1.0.0` — the version
/// every T2 corpus fixture emits (`"schema_version": "1.0"`).
pub const MIN_SCHEMA: (u32, u32, u32) = (1, 0, 0);

/// Exclusive upper bound. `2.0.0` and anything at/above it is as fatal as
/// anything below `MIN_SCHEMA` — the contract's "older is as fatal as
/// newer" is symmetric, so this is an exclusive bound, not an inclusive max.
pub const MAX_SCHEMA_EXCLUSIVE: (u32, u32, u32) = (2, 0, 0);

/// Parses `"MAJOR.MINOR[.PATCH]"` into a comparable tuple. Returns `None`
/// for anything that doesn't match that shape (non-numeric, wrong arity).
/// The caller treats "unparseable" exactly as fatally as "numerically out of
/// range" — there is no separate `CliUnreadableReason` for a malformed
/// version string, since a version we can't even parse is definitionally one
/// we can't trust the range of.
pub fn parse_schema_version(raw: &str) -> Option<(u32, u32, u32)> {
    let mut parts = raw.split('.');
    let major = parts.next()?.parse::<u32>().ok()?;
    let minor = parts.next()?.parse::<u32>().ok()?;
    let patch = match parts.next() {
        Some(p) => p.parse::<u32>().ok()?,
        None => 0,
    };
    if parts.next().is_some() {
        return None; // more than 3 dot-separated components — not this contract's shape
    }
    Some((major, minor, patch))
}

/// `MIN_SCHEMA <= v < MAX_SCHEMA_EXCLUSIVE`, both directions gated.
pub fn schema_version_in_range(v: (u32, u32, u32)) -> bool {
    v >= MIN_SCHEMA && v < MAX_SCHEMA_EXCLUSIVE
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_and_three_component_versions_parse() {
        assert_eq!(parse_schema_version("1.0"), Some((1, 0, 0)));
        assert_eq!(parse_schema_version("1.5.2"), Some((1, 5, 2)));
    }

    #[test]
    fn in_range_versions_pass() {
        assert!(schema_version_in_range(
            parse_schema_version("1.0").unwrap()
        ));
        assert!(schema_version_in_range(
            parse_schema_version("1.5.2").unwrap()
        ));
        assert!(schema_version_in_range(
            parse_schema_version("1.999.999").unwrap()
        ));
    }

    #[test]
    fn below_min_is_out_of_range() {
        assert!(!schema_version_in_range(
            parse_schema_version("0.9").unwrap()
        ));
        assert!(!schema_version_in_range(
            parse_schema_version("0.99.99").unwrap()
        ));
    }

    #[test]
    fn at_or_above_max_is_out_of_range() {
        assert!(!schema_version_in_range(
            parse_schema_version("2.0").unwrap()
        ));
        assert!(!schema_version_in_range(
            parse_schema_version("3.1.4").unwrap()
        ));
    }

    #[test]
    fn malformed_versions_fail_to_parse() {
        assert_eq!(parse_schema_version("abc"), None);
        assert_eq!(parse_schema_version("1"), None);
        assert_eq!(parse_schema_version("1.2.3.4"), None);
        assert_eq!(parse_schema_version(""), None);
        assert_eq!(parse_schema_version("1.x"), None);
    }
}
