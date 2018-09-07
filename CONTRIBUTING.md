# Contributing

## Pull Requests

1.  Pull requests should not be done in **master**:

    ```bash
    git checkout -b topic/name
    ```

    This is not necessary for small changes, e.g. fixing typos in `README.md`.

1.  Pull requests must be **rebased** on the latest **master** from the
    **upstream** repository:

    ```bash
    # add the upstream repository as remote
    git remote add upstream https://github.com/idiv-biodiversity/scddl.git

    # fetch latest upstream commits
    git fetch upstream

    # rebase your branch on master
    git rebase upstream/master topic/name
    ```

1.  All download tools must be accompanied with a short example in
    `.travis.yml`. Please pick a small data set so the tests won't run forever.
