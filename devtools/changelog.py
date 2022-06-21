#!/usr/bin/env python3
# Copied from ElementsProject/lightning, thanks! :)

from collections import namedtuple
from datetime import datetime
from mako.template import Template
import argparse
import os
import re
import requests
import shlex
import subprocess
import sys

# What sections do we support in the changelog:
sections = [
    'added',
    'changed',
    'deprecated',
    'fixed',
    'removed',
    'experimental',
]

repo = 'damus-io/damus'

Entry = namedtuple("Entry", ["commit", "pullreq", "content", "section"])
Link = namedtuple("Link", ["ref", "content", "url"])


def git(cmd):
    cmd = shlex.split(cmd)
    out = subprocess.check_output(['git'] + cmd)
    return out.decode('UTF-8')


def get_commit_range():
    """Find a commit range that we should collect the CHANGELOG for.
    """
    description = git("describe")
    version = description.split('-')[0]
    return "{version}..master".format(version=version)


def get_log_entries(commitrange):
    commit = None
    logs = git("log {commitrange}".format(commitrange=commitrange))
    entries = []

    for l in logs.split('\n'):
        m = re.match(r'^commit ([A-Fa-f0-9]{40})$', l)
        if m:
            commit = m.group(1)

        m = re.match(
            r'^\s+Changelog-({}): (.*)$'.format("|".join(sections)), l, re.IGNORECASE)
        if not m:
            continue

        # Now try to resolve the pull request that originated this commit:
        headers = {
            'Accept': 'application/vnd.github.groot-preview+json',
        }

        if os.environ.get('GH_TOKEN'):
            headers['Authorization'] = 'token ' + os.environ.get('GH_TOKEN')

        url = 'https://api.github.com/repos/{repo}/commits/{commit}/pulls'.format(repo=repo, commit=commit)
        content = requests.get(url, headers=headers).json()
        if content and content.get(0) is not None:
            pullreq = content[0]['number']
        else:
            pullreq = None

        e = Entry(commit, pullreq, m.group(2), m.group(1).lower())
        entries.append(e)

    return entries


def linkify(entries):
    links = []
    for e in entries:
        if e.pullreq is not None:
            links.append(Link(
                ref='#{}'.format(e.pullreq),
                content=e.content,
                url="https://github.com/{repo}/pull/{pullreq}".format(repo=repo, pullreq=e.pullreq)
            ))
    return list(set(links))


def group(entries):
    groups = {s: [] for s in sections}
    for e in entries:
        groups[e.section].append(e)
    for s in sections:
        if len(groups[s]) == 0:
            del groups[s]
    return groups


def commit_date(commitsha):
    """Get the date of the specified commit.
    """
    line = git("show -s --format=%ci")
    dt = datetime.strptime(line.strip(), '%Y-%m-%d %H:%M:%S %z')
    return dt


template = Template("""<%def name="group(entries)">
% for e in entries:
 % if e.pullreq is not None:
     - ${e.content} ([#${e.pullreq}])
 % else:
     - ${e.content}
 % endif
% endfor

</%def><%def name="group_links(entries)">
% for e in entries:
[${e.pullreq}]: https://github.com/${repo}/pull/${e.pullreq}
% endfor
</%def>

${h2} [${version}] - ${date.strftime("%Y-%m-%d")}

% for section in sections:
${h3} ${section.capitalize()}
${group(groups[section]) | trim}
% endfor

% for l in links:
[${l.ref}]: ${l.url}
% endfor
[${version}]: https://github.com/${repo}/releases/tag/v${version}""")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Generate a changelog summary for a given commit range'
    )
    parser.add_argument('commitrange', type=str, nargs='?',
                        help='Range of commits to consider (format: <from_commit>..<to_commit>',
                        default=get_commit_range())

    args = parser.parse_args()

    if '..' not in args.commitrange:
        print("Commit range must include '..' to separate 'from_commit' and 'to_commit'")
        sys.exit(1)

    fromcommit, tocommit = args.commitrange.split('..')
    entries = get_log_entries(args.commitrange)
    groups = group(entries)
    date = commit_date(tocommit)

    print(template.render(
        groups=groups,
        repo=repo,
        sections=groups.keys(),
        h2='##',
        h3='###',
        version=tocommit[1:],
        date=date,
        links=linkify(entries),
    ))


