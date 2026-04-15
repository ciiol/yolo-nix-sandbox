mod bwrap;
mod cli;
mod etc;
mod sandbox;
mod uid;

use std::os::unix::process::ExitStatusExt;

use clap::Parser;
use cli::Cli;

fn main() {
    let cli = Cli::parse();
    let command = cli.command.resolve();

    let status = match sandbox::run(command) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("yolo: {e:#}");
            std::process::exit(1);
        }
    };

    // Match bash convention: signal-killed processes exit with 128 + signal number
    std::process::exit(
        status
            .code()
            .unwrap_or_else(|| status.signal().map_or(1, |s| 128 + s)),
    );
}
