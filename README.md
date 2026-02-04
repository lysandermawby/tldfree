# TLDFree - Find Free Domains

Speed up your search for the perfect domain. Given a keyword, TLDFree will search for available domains across all possible TLD extensions. 

By using the `whois` or `ping` commands, this script checks for records of any domains using your preferred keyword. This allows you to check all possible domains in mere minutes.

## Quick Start

First, make the underlying script executable.

```bash
chmod +x tldfree.sh
```

Then run it with some domain name you would like to check.

```bash
./tldfree.sh "your_domain_name"
```

To use this script anywhere in your system, consider adding an alias to your `~/.zshrc` or `~/.bashrc` file as appropriate.

```bash
alias tldfree='/path/to/tldfree/tldfree.sh' 
```

## Update TLDs

The IANA maintains a [TLDs list](https://data.iana.org/TLD/tlds-alpha-by-domain.txt), giving all available TLDs.

Run this script with the `-u|--update` option to update your list of tlds. Note that this uses [Punycode](https://en.wikipedia.org/wiki/Punycode).

If you would not like to keep a record of your previous TLDs list, run this with the `--no-backup-tlds` option.

## Troubleshooting

To see all command line options related to this script, run it with the `-h|--help` option.

```bash
./tldfree.sh --help
```

You will see help information such as the following:

```bash
tldfree - Find available domains.

USAGE:
    tldfree [OPTIONS] <domain name> [--tlds]

OPTIONS:
    -h|--help           Show this help message
    -v|--version        Display script version
    -u|--update         Update the list of tlds
    -t|--taken          Only show taken domains
    -a|--available      Only show available domains
    --whois             Force whois lookup (fail if whois is not installed)
    --ping              Force ping lookup
    --no-backup-tlds    Do not make a backup of the current tlds list
    --tlds              Search only these tlds

EXAMPLE:
    tldfree google --tlds com org net
```
