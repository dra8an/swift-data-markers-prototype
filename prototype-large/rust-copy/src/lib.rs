// The Rust copy of the Swift design. The generated data is part of this crate, because Rust allows an impl of a trait for a type only in the crate of the trait or of the type.
pub mod chinese_years;
pub mod data_markers;
pub mod fallback_tables;
pub mod format;

#[allow(clippy::all)]
mod data {
    include!(env!("RUST_COPY_DATA"));
}
