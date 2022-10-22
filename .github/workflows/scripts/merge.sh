# Get the current commit hash so we can compare later
oldCommit=$(git log --pretty=format:'%h' -n 1)

# Set username and email vars
git config --global user.name $GHUSER
git config --global user.email $GHEMAIL
git pull --unshallow  # this option is very important, you would get
                      # complains about unrelated histories without it.
                      # (but actions/checkout@v2 can also be instructed
                      # to fetch all git depth right from the start)
# Set the upstream repo, fetch, merge, and push
git remote add upstream https://github.com/freqstart/freqstart
git fetch upstream
git merge upstream/stable
git push origin stable
# Get the new commit hash to compare
newCommit=$(git log --pretty=format:'%h' -n 1)

if [[ "$oldCommit" == "$newCommit" ]]
then
  echo Commit $newCommit is unchanged!!!
  exit
fi

if [[ "$oldCommit" != "$newCommit" ]]
then
  echo Commit is updated!!! New commit hash is $newCommit
  exit
fi