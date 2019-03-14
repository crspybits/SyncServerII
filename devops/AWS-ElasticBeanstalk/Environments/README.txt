These folders are where you run the eb cli.

To initialize the folder, with the basic environment setup, do:
eb init

(also see Docs/LaunchingEnvironment.md)

Later, e.g., in the sharedimages-staging folder, you create (start) an environment with:
eb create sharedimages-staging --cname sharedimages-staging