# Contributing

## Submitting patches

*Most of this comes from the linux kernel guidelines for submitting
patches, we follow many of the same guidelines. These are very important!
If you want your code to be accepted, please read this carefully*

Describe your problem.  Whether your patch is a one-line bug fix or
5000 lines of a new feature, there must be an underlying problem that
motivated you to do this work.  Convince the reviewer that there is a
problem worth fixing and that it makes sense for them to read past the
first paragraph.

Once the problem is established, describe what you are actually doing
about it in technical detail.  It's important to describe the change
in plain English for the reviewer to verify that the code is behaving
as you intend it to.

The maintainer will thank you if you write your patch description in a
form which can be easily pulled into Damus's source code tree.

**Solve only one problem per patch**.  If your description starts to get
long, that's a sign that you probably need to split up your patch. See
the dedicated `Separate your changes` section because this is very
important.

Describe your changes in imperative mood, e.g. "make xyzzy do frotz"
instead of "[This patch] makes xyzzy do frotz" or "[I] changed xyzzy
to do frotz", as if you are giving orders to the codebase to change
its behaviour.

If your patch fixes a bug, use the 'Closes:' tag with a URL referencing
the report in the mailing list archives or a public bug tracker. For
example:

	Closes: https://github.com/damus-io/damus/issues/1234

Some bug trackers have the ability to close issues automatically when a
commit with such a tag is applied. Some bots monitoring mailing lists can
also track such tags and take certain actions. Private bug trackers and
invalid URLs are forbidden.

If your patch fixes a bug in a specific commit, e.g. you found an issue using
``git bisect``, please use the 'Fixes:' tag with the first 12 characters of
the SHA-1 ID, and the one line summary.  Do not split the tag across multiple
lines, tags are exempt from the "wrap at 75 columns" rule in order to simplify
parsing scripts.  For example::

	Fixes: 54a4f0239f2e ("Fix crash in navigation")

The following ``git config`` settings can be used to add a pretty format for
outputting the above style in the ``git log`` or ``git show`` commands::

	[core]
		abbrev = 12
	[pretty]
		fixes = Fixes: %h (\"%s\")

An example call::

	$ git log -1 --pretty=fixes 54a4f0239f2e
	Fixes: 54a4f0239f2e ("Fix crash in navigation")


### Separate your changes

Separate each **logical change** into a separate patch.

For example, if your changes include both bug fixes and performance
enhancements for a particular feature, separate those changes into two or
more patches.  If your changes include an API update, and a new feature
which uses that new API, separate those into two patches.

On the other hand, if you make a single change to numerous files, group
those changes into a single patch.  Thus a single logical change is
contained within a single patch.

The point to remember is that each patch should make an easily understood
change that can be verified by reviewers.  Each patch should be justifiable
on its own merits.

When dividing your change into a series of patches, take special care to
ensure that the Damus builds and runs properly after each patch in the
series.  Developers using ``git bisect`` to track down a problem can end
up splitting your patch series at any point; they will not thank you if
you introduce bugs in the middle.

If you cannot condense your patch set into a smaller set of patches,
then only post say 15 or so at a time and wait for review and integration.

Include `patch changelogs` which describe what has changed between the v1 and
v2 version of the patch. 

### Sign your work - the Developer's Certificate of Origin

To improve tracking of who did what, especially with patches that can
percolate to their final resting place in the Damus through several
layers of maintainers, we've introduced a "sign-off" procedure on
patches that are being emailed around.

The sign-off is a simple line at the end of the explanation for the
patch, which certifies that you wrote it or otherwise have the right to
pass it on as an open-source patch.  The rules are pretty simple: if you
can certify the below:

Developer's Certificate of Origin 1.1
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

By making a contribution to this project, I certify that:

        (a) The contribution was created in whole or in part by me and I
            have the right to submit it under the open source license
            indicated in the file; or

        (b) The contribution is based upon previous work that, to the best
            of my knowledge, is covered under an appropriate open source
            license and I have the right under that license to submit that
            work with modifications, whether created in whole or in part
            by me, under the same open source license (unless I am
            permitted to submit under a different license), as indicated
            in the file; or

        (c) The contribution was provided directly to me by some other
            person who certified (a), (b) or (c) and I have not modified
            it.

        (d) I understand and agree that this project and the contribution
            are public and that a record of the contribution (including all
            personal information I submit with it, including my sign-off) is
            maintained indefinitely and may be redistributed consistent with
            this project or the open source license(s) involved.

then you just add a line saying:

	Signed-off-by: Random J Developer <random@developer.example.org>

This will be done for you automatically if you use `git commit -s`.
Reverts should also include "Signed-off-by". `git revert -s` does that
for you.

Any further SoBs (Signed-off-by:'s) following the author's SoB are from
people handling and transporting the patch, but were not involved in its
development. SoB chains should reflect the **real** route a patch took
as it was propagated to the maintainers and ultimately to Will, with
the first SoB entry signalling primary authorship of a single author.

### Add Changelog-Changed, Changelog-Fixed, etc

If you have a *user facing* change that you would like to include in Damus
changelogs, please include:

- Changelog-Changed: Changed the heart button to a shaka
- Changelog-Fixed: Fixed notes not appearing on profile
- Changelog-Added: Added a cool new feature
- Changelog-Removed: Removed zaps

The changelog script will pick these up and give you attribution for your
change

