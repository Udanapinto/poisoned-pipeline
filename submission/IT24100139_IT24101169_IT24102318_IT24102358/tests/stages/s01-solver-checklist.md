# S01 - The Git Leak Solver Checklist

## Clean Start

- [ ] Repository accessible without authentication
- [ ] Repository clone succeeds through Nginx
- [ ] Current branch contains no S01 flag
- [ ] Current branch contains no Jenkins credential

## Intended Path

- [ ] Inspect repository
- [ ] Inspect commit history
- [ ] Inspect suspicious change/diff
- [ ] Recover S01 token
- [ ] Recover Jenkins username
- [ ] Recover Jenkins password
- [ ] Recover Jenkins build-job clue
- [ ] Record the relevant commit ID
- [ ] Submit S01 token to CTFd

## Negative Checks

- [ ] Flag is not present in current files
- [ ] Jenkins credential is not present in current files
- [ ] Gitea TCP 3000 is not host-published
- [ ] Gitea belongs only to control_net
- [ ] S01 cannot be solved from repository title alone