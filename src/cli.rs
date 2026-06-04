use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "yolo",
    version,
    about = "Run commands in a sandboxed environment"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Run an arbitrary command in the sandbox
    Run {
        #[arg(required = true, trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Run Claude with --dangerously-skip-permissions
    #[command(disable_help_flag = true)]
    Claude {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Run Codex with --yolo
    #[command(disable_help_flag = true)]
    Codex {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Run Gemini with --yolo
    #[command(disable_help_flag = true)]
    Gemini {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Run Ralphex
    #[command(disable_help_flag = true)]
    Ralphex {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Run pi-coding-agent
    #[command(disable_help_flag = true)]
    Pi {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
}

impl Command {
    pub fn resolve(self) -> Vec<String> {
        match self {
            Command::Run { args } => args,
            Command::Claude { args } => {
                let mut resolved = vec![
                    "claude".to_string(),
                    "--dangerously-skip-permissions".to_string(),
                ];
                resolved.extend(args);
                resolved
            }
            Command::Codex { args } => {
                let mut resolved = vec!["codex".to_string(), "--yolo".to_string()];
                resolved.extend(args);
                resolved
            }
            Command::Gemini { args } => {
                let mut resolved = vec!["gemini".to_string(), "--yolo".to_string()];
                resolved.extend(args);
                resolved
            }
            Command::Ralphex { args } => {
                let mut resolved = vec!["ralphex".to_string()];
                resolved.extend(args);
                resolved
            }
            Command::Pi { args } => {
                let mut resolved = vec!["pi".to_string()];
                resolved.extend(args);
                resolved
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::error::ErrorKind;

    fn parse(args: &[&str]) -> Result<Cli, clap::Error> {
        Cli::try_parse_from(args)
    }

    #[test]
    fn run_requires_args() {
        let err = parse(&["yolo", "run"]).unwrap_err();
        assert_eq!(err.kind(), ErrorKind::MissingRequiredArgument);
    }

    #[test]
    fn run_with_command() {
        let cli = parse(&["yolo", "run", "bash", "-c", "echo hi"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["bash", "-c", "echo hi"]);
    }

    #[test]
    fn claude_no_args() {
        let cli = parse(&["yolo", "claude"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["claude", "--dangerously-skip-permissions"]);
    }

    #[test]
    fn claude_with_args() {
        let cli = parse(&["yolo", "claude", "--model", "opus"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(
            resolved,
            vec![
                "claude",
                "--dangerously-skip-permissions",
                "--model",
                "opus"
            ]
        );
    }

    #[test]
    fn codex_no_args() {
        let cli = parse(&["yolo", "codex"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["codex", "--yolo"]);
    }

    #[test]
    fn codex_with_args() {
        let cli = parse(&["yolo", "codex", "prompt"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["codex", "--yolo", "prompt"]);
    }

    #[test]
    fn gemini_no_args() {
        let cli = parse(&["yolo", "gemini"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["gemini", "--yolo"]);
    }

    #[test]
    fn gemini_with_args() {
        let cli = parse(&["yolo", "gemini", "extra"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["gemini", "--yolo", "extra"]);
    }

    #[test]
    fn ralphex_no_args() {
        let cli = parse(&["yolo", "ralphex"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["ralphex"]);
    }

    #[test]
    fn ralphex_with_args() {
        let cli = parse(&["yolo", "ralphex", "--plan", "foo"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["ralphex", "--plan", "foo"]);
    }

    #[test]
    fn pi_no_args() {
        let cli = parse(&["yolo", "pi"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["pi"]);
    }

    #[test]
    fn pi_with_args() {
        let cli = parse(&["yolo", "pi", "--model", "foo"]).unwrap();
        let resolved = cli.command.resolve();
        assert_eq!(resolved, vec!["pi", "--model", "foo"]);
    }

    #[test]
    fn passthrough_subcommands_forward_help_flag() {
        // `--help` must reach the wrapped tool, not be intercepted by clap's
        // generated help for the subcommand.
        for (sub, expected) in [
            (
                "claude",
                vec!["claude", "--dangerously-skip-permissions", "--help"],
            ),
            ("codex", vec!["codex", "--yolo", "--help"]),
            ("gemini", vec!["gemini", "--yolo", "--help"]),
            ("ralphex", vec!["ralphex", "--help"]),
            ("pi", vec!["pi", "--help"]),
        ] {
            let cli = parse(&["yolo", sub, "--help"]).unwrap();
            assert_eq!(cli.command.resolve(), expected, "subcommand {sub}");
        }
    }

    #[test]
    fn unknown_subcommand_errors() {
        let err = parse(&["yolo", "unknown"]).unwrap_err();
        assert_eq!(err.kind(), ErrorKind::InvalidSubcommand);
    }

    #[test]
    fn no_subcommand_errors() {
        let err = parse(&["yolo"]).unwrap_err();
        assert_eq!(
            err.kind(),
            ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand
        );
    }

    #[test]
    fn help_flag() {
        let err = parse(&["yolo", "--help"]).unwrap_err();
        assert_eq!(err.kind(), ErrorKind::DisplayHelp);
    }
}
