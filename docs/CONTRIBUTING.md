# Contributing

You can use github PRs to submit code but it is not encouraged. Damus is
a decentralized social media protocol and we prefer to use decentralized
techniques during the code submission process.

[Email patches][git-send-email] to patches@damus.io are preferred, but we
accept PRs on GitHub as well. Patches sent via email may include a bolt11
lightning invoice, choosing the price you think the patch is worth, and
we will pay it once the patch is accepted and if I think the price isn't
unreasonable. You can also send an any-amount invoice and I will pay what
I think it's worth if you prefer not to choose. You can include the
bolt11 in the commit body or email so that it can be paid once it is
applied.

Recommended settings when submitting code via email:

```
$ git config sendemail.to "patches@damus.io"
$ git config format.subjectPrefix "PATCH damus"
$ git config format.signOff yes
```

You can subscribe to the [patches mailing list][patches-ml] to help review code.

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

When you submit or resubmit a patch or patch series, include the complete
patch description and justification for it. Each new version should use
the -v2,v3,vN option on git-send-email for each new patch revision. Don't
just say that this is version N of the patch (series).  Don't expect the
reviewer to refer back to earlier patch versions or referenced URLs to
find the patch description and put that into the patch. I.e., the patch
(series) and its description should be self-contained. This benefits both
the maintainers and reviewers.  Some reviewers probably didn't even
receive earlier versions of the patch.

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

If one patch depends on another patch in order for a change to be
complete, that is OK.  Simply note **"this patch depends on patch X"**
in your patch description.

When dividing your change into a series of patches, take special care to
ensure that the Damus builds and runs properly after each patch in the
series.  Developers using ``git bisect`` to track down a problem can end
up splitting your patch series at any point; they will not thank you if
you introduce bugs in the middle.

If you cannot condense your patch set into a smaller set of patches,
then only post say 15 or so at a time and wait for review and integration.

Include `patch changelogs` which describe what has changed between the v1 and
v2 version of the patch. Please put this information **after** the `---` line
which separates the changelog from the rest of the patch. The version
information is not part of the changelog which gets committed to the git tree.
It is additional information for the reviewers. If it's placed above the commit
tags, it needs manual interaction to remove it. If it is below the separator
line, it gets automatically stripped off when applying the patch::

    <commit message>
    ...
    Signed-off-by: Author <author@mail>
    ---
    V2 -> V3: Removed redundant helper function
    V1 -> V2: Cleaned up coding style and addressed review comments
    
    path/to/file | 5+++--
    ...


### Select the recipients for your patch

You should always copy the appropriate people on any patch to code that
they may have been involved with. You can use
[git-contacts][git-contacts] to find people who have touched the code
previously:

    $ git format-patch --cover-letter -o patches origin/master..my-feature
    $ git send-email --dry-run --cc-cmd=git-contacts patches/*

patches@damus.io should be used by default for all patches.

William Casarin is the final arbiter of all changes accepted into the
Damus.  His email address is <jb55@jb55.com>.

If you have a patch that fixes an exploitable security bug, send that
patch to jb55@jb55.com.  For severe bugs, a short embargo may be
considered to allow distributors to get the patch out to users; in such
cases, obviously, the patch should not be sent to any public lists.

### No MIME, no links, no compression, no attachments. Just plain text.

Will and other Damus developers need to be able to read and comment
on the changes you are submitting.  It is important for a Damus
developer to be able to "quote" your changes, using standard e-mail
tools, so that they may comment on specific portions of your code.

For this reason, all patches should be submitted by e-mail "inline". The
easiest way to do this is with `git send-email`, which is strongly
recommended.  An interactive tutorial for `git send-email` is available at
[git-send-email][git-send-email]

### Respond to review comments

Your patch will almost certainly get comments from reviewers on ways in
which the patch can be improved, in the form of a reply to your email. You must
respond to those comments; ignoring reviewers is a good way to get ignored in
return. You can simply reply to their emails to answer their comments. Review
comments or questions that do not lead to a code change should almost certainly
bring about a comment or changelog entry so that the next reviewer better
understands what is going on.

Be sure to tell the reviewers what changes you are making and to thank them
for their time.  Code review is a tiring and time-consuming process, and
reviewers sometimes get grumpy.  Even in that case, though, respond
politely and address the problems they have pointed out.  When sending a next
version, add a `patch changelog` to the cover letter or to individual patches
explaining difference against previous submission (see `The canonical patch format`)


### Use trimmed interleaved replies in email discussions

Top-posting is strongly discouraged in Damus development
discussions. Interleaved (or "inline") replies make conversations much
easier to follow. For more details see: [Posting style][posting-style]

As is frequently quoted on the mailing list:

  A: http://en.wikipedia.org/wiki/Top_post
  Q: Were do I find info about this thing called top-posting?
  A: Because it messes up the order in which people normally read text.
  Q: Why is top-posting such a bad thing?
  A: Top-posting.
  Q: What is the most annoying thing in e-mail?

Similarly, please trim all unneeded quotations that aren't relevant
to your reply. This makes responses easier to find, and saves time and
space. For more details see: http://daringfireball.net/2007/07/on_top

  A: No.
  Q: Should I include quotations after my reply?


### Sign your work - the Developer's Certificate of Origin

To improve tracking of who did what, especially with patches that can
percolate to their final resting place in the kernel through several
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

### When to use Acked-by:, Cc:, and Co-developed-by:

The Signed-off-by: tag indicates that the signer was involved in the
development of the patch, or that he/she was in the patch's delivery path.

If a person was not directly involved in the preparation or handling of a
patch but wishes to signify and record their approval of it then they can
ask to have an Acked-by: line added to the patch's changelog.

Acked-by: is often used by the maintainer of the affected code when that
maintainer neither contributed to nor forwarded the patch.

Acked-by: is not as formal as Signed-off-by:.  It is a record that the acker
has at least reviewed the patch and has indicated acceptance.  Hence patch
mergers will sometimes manually convert an acker's "yep, looks good to me"
into an Acked-by: (but note that it is usually better to ask for an
explicit ack).

Acked-by: does not necessarily indicate acknowledgement of the entire patch.
For example, if a patch affects multiple subsystems and has an Acked-by: from
one subsystem maintainer then this usually indicates acknowledgement of just
the part which affects that maintainer's code.  Judgement should be used here.
When in doubt people should refer to the original discussion in the mailing
list archives.

If a person has had the opportunity to comment on a patch, but has not
provided such comments, you may optionally add a ``Cc:`` tag to the patch.
This is the only tag which might be added without an explicit action by the
person it names - but it should indicate that this person was copied on the
patch.  This tag documents that potentially interested parties
have been included in the discussion.

Co-developed-by: states that the patch was co-created by multiple developers;
it is used to give attribution to co-authors (in addition to the author
attributed by the From: tag) when several people work on a single patch.  

### Using Reported-by:, Tested-by:, Reviewed-by:, Suggested-by: and Fixes:

The Reported-by tag gives credit to people who find bugs and report them and it
hopefully inspires them to help us again in the future. The tag is intended for
bugs; please do not use it to credit feature requests. The tag should be
followed by a Closes: tag pointing to the report, unless the report is not
available on the web. The Link: tag can be used instead of Closes: if the patch
fixes a part of the issue(s) being reported. Please note that if the bug was
reported in private, then ask for permission first before using the Reported-by
tag.

A Tested-by: tag indicates that the patch has been successfully tested (in
some environment) by the person named.  This tag informs maintainers that
some testing has been performed, provides a means to locate testers for
future patches, and ensures credit for the testers.

Reviewed-by:, instead, indicates that the patch has been reviewed and found
acceptable according to the Reviewer's Statement:

A Reviewed-by tag is a statement of opinion that the patch is an
appropriate modification of Damus and related libraies without any
remaining serious technical issues.  Any interested reviewer (who has
done the work) can offer a Reviewed-by tag for a patch.  This tag serves
to give credit to reviewers and to inform maintainers of the degree of
review which has been done on the patch.  Reviewed-by: tags, when
supplied by reviewers known to understand the subject area and to perform
thorough reviews, will normally increase the likelihood of your patch
getting into Damus.

Both Tested-by and Reviewed-by tags, once received on mailing list from tester
or reviewer, should be added by author to the applicable patches when sending
next versions.  However if the patch has changed substantially in following
version, these tags might not be applicable anymore and thus should be removed.
Usually removal of someone's Tested-by or Reviewed-by tags should be mentioned
in the patch changelog (after the '---' separator).

A Suggested-by: tag indicates that the patch idea is suggested by the person
named and ensures credit to the person for the idea. Please note that this
tag should not be added without the reporter's permission, especially if the
idea was not posted in a public forum. That said, if we diligently credit our
idea reporters, they will, hopefully, be inspired to help us again in the
future.

### Explicit In-Reply-To headers

It can be helpful to manually add In-Reply-To: headers to a patch
(e.g., when using ``git send-email``) to associate the patch with
previous relevant discussion, e.g. to link a bug fix to the email with
the bug report.  However, for a multi-patch series, it is generally
best to avoid using In-Reply-To: to link to older versions of the
series.  This way multiple versions of the patch don't become an
unmanageable forest of references in email clients.

### Providing base tree information

When other developers receive your patches and start the review process,
it is often useful for them to know where in the tree history they
should place your work. This is particularly useful for automated CI
processes that attempt to run a series of tests in order to establish
the quality of your submission before the maintainer starts the review.

If you are using `git format-patch` to generate your patches, you can
automatically include the base tree information in your submission by
using the `--base` flag. The easiest and most convenient way to use
this option is with topical branches:

    $ git checkout -t -b my-topical-branch master
    Branch 'my-topical-branch' set up to track local branch 'master'.
    Switched to a new branch 'my-topical-branch'

    [perform your edits and commits]

    $ git format-patch --base=auto --cover-letter -o outgoing/ master
    outgoing/0000-cover-letter.patch
    outgoing/0001-First-Commit.patch
    outgoing/...

When you open `outgoing/0000-cover-letter.patch` for editing, you will
notice that it will have the `base-commit:` trailer at the very
bottom, which provides the reviewer and the CI tools enough information
to properly perform `git am` without worrying about conflicts::

    $ git checkout -b patch-review [base-commit-id]
    Switched to a new branch 'patch-review'
    $ git am patches.mbox
    Applying: First Commit
    Applying: ...

Please see ``man git-format-patch`` for more information about this
option.

[git-contacts]: https://github.com/git/git/blob/master/contrib/contacts/git-contacts
[git-send-email]: http://git-send-email.io
[patches-ml]: https://damus.io/list/patches
[posting-style]: https://en.wikipedia.org/wiki/Posting_style#Interleaved_style
