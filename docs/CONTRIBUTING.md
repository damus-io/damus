# Contributing

Making contributions takes significant effort and time from both the contributor 
and the person who will review your work.

We made these guidelines to help you make successful contributions and avoid
wasted time and effort! So even though it might require a bit of extra time 
to read these, it will likely save you a lot of time and headaches while 
making contributions.

*Most of this comes from the linux kernel guidelines for submitting
patches, we follow many of the same guidelines. These are very important!
If you want your code to be accepted, please read these carefully*

## Choosing the scope of your contribution

Since reviews require time and effort from our busy team, it is important to
carefully choose the scope of your work.

If your contributions are long and difficult to review and/or verify,
or if they do not solve something that is of high priority for the team,
you may find that your contributions may take much longer to get merged,
or they may get rejected completely.

If this is your first time contributing, we *strongly* recommend starting small,
and then working your way up to larger contributions as you get familiar with
the entire process.

## Submitting patches/PRs

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

### Testing

It is crucial that you properly test your changes. The reviewer needs to be
convinced that your changes actually work, solve the issue at hand, and do not 
introduce new issues.

Therefore, with every PR/patch, you should include a report indicating what was
tested, under what circumstances (e.g. Devices, devices, setup, etc.), and how.

The goal is not to overburden the contributor, but to allow the reviewer to 
independently verify the claims being made about the contribution as needed.
Therefore, test reports should be specific enough that the reviewer 
can independently verify them.

The more complex and widespread your changes, the more testing it will require.

If the reviewer cannot verify your claims in a time-efficient manner, you may be
asked to perform further testing, and/or experience delays.

DON'T:
❌ Provide vague test reports.
❌ Make big changes and not provide enough test coverage.
❌ Expect the reviewer to do a lot of testing on your behalf.
❌ Underestimate how much testing and polish bigger changes actually need.

DO:
✅ Provide enough details about your testing so that the reviewer can verify quality.
✅ Make it easy for the reviewer to understand that your changes actually work.

#### Recreating and root-causing issues

If your contribution tries to fix an existing issue, please try to ensure that
you can recreate the original issue, or can reasonably prove its root cause 
with sound logic, before making the fix.

Without the ability to recreate the issue, it is near impossible to know 
if a successful test result is due to a successful fix, or simply "luck".

Ideally, there should be a specific test procedure that clearly fails
before your changes, and clearly passes after your changes.

If you are solving an issue that is easy or "obvious" to recreate, you may not
need this. However, if you are solving difficult or intermittent 
issues, this is very important. Many times it is where most of the work really is!

For intermittent issues, please perform several iterations of the tests 
until you can confidently assert the issue is really fixed.

DON'T:
❌ Claim an intermittent issue is fixed simply because some test procedure passes.
❌ Expect the reviewer to find the issue recreation steps for you.

DO:
✅ Find a procedure that recreates the issue before changes are applied.
✅ Be consistent with the procedure applied for issue recreation and fix verification.
✅ Run enough iterations of testing for intermittent issues.
✅ Provide sound reasoning for your fix when it is impractical to recreate the issue.


## Submitting multiple PRs

Unless otherwise needed by our priorities and roadmap, our team will only work 
and prioritize one PR per author at a time to ensure every PR author has a chance 
to get their PR reviewed, and incentivize all contributors to prioritize 
driving existing PRs to the finish line.

If you submit multiple PRs at a time, our team will pick a PR to focus on first, and
label other PRs as being on a "queue". If this happens, please focus on addressing
issues on an existing PR over opening a new PR.

The above rule may be waived as needed by the team to fulfill its priorities.


## AI-assisted contributions

We embrace and encourage new technologies and innovations in our product development.
Therefore, AI-assisted contributions are welcome in this repository. 
However, AI-assisted submissions will be treated with the same standards and rigour
as any other human-made submissions. Therefore, AI-assisted submissions must also
follow all these guidelines.

If you do not have any Software Engineering experience, please consider the following:
- Make sure you have the proper rights to submit the AI-generated code.
- Make sure you are able to "own" your contributions — meaning that you can attend to
  requests and feedback our reviewers make.

Although we endeavour to be helpful when making requests back to PR/patch authors, 
we are under no obligation to provide extensive assistance to AI-assisted contributors 
who have significant gaps in their Software Engineering knowledge.

As mentioned at the top, we encourage all contributors to start with small contributions,
to become familiar with the process. We believe this will increase your chances of success!

## Questions about the guidelines

Feel free to ask our team about questions you may have regarding these guidelines, we will
be happy to clarify any of the above items!

Thank you for contributing to Damus!

