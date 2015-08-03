# goget.sh: a little bit more than go get
`goget.sh` is an all-in-one script to install a go package.
Before installing your package, it first installs go and
initializes the go workspace (i.e., `$GOPATH`) if needed.
It is designed for an easier setup process; mainly for the
newcomers and people who are interested in a project but
not necessarily programming in go.

This is how to install an example package:
```bash
curl -sL https://git.io/goget | bash -s -- github.com/soheilhy/cmux
```

![goget demo](http://raw.github.com/soheilhy/goget/master/assets/goget.gif)


For go users, it is just like `go get`.
