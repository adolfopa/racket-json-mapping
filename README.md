racket-json-mapping
===================

A simple syntactic form to map jsexpr to racket structs.

Until I write some proper documentation, a simple example should
suffice to understand how `json-mapping` works.

Suppose you have a snippet of JSON like the following:

    (define gist-json
    #<<EOF
      {
        "url": "https://api.github.com/gists/c626a4c4ca64bcf2495d",
        "id": "1",
        "description": "description of gist",
        "public": true,
        "user": {
          "login": "octocat",
          "id": 1,
          "avatar_url": "https://github.com/images/error/octocat_happy.gif",
          "gravatar_id": "somehexcode",
          "url": "https://api.github.com/users/octocat"
        },
        "comments": 0,
        "comments_url": "https://api.github.com/gists/be4c76671c1377828fb5/comments/",
        "html_url": "https://gist.github.com/1",
        "git_pull_url": "git://gist.github.com/1.git",
        "git_push_url": "git@gist.github.com:1.git",
        "created_at": "2010-04-14T02:15:15Z"
      }
    EOF
    )

You can read it easily with the `json` package, but mapping the Jsexpr
to the final representation of the data in your application requires a
moderate ammount of boilerplate. With the `json-mapping` package, you
simply declare the "shape" of your data, and it will generate the
necessary code to map from Racket data to jsexpr and viceversa.

    (require json)
    (require json-mapping)

    (define jsexpr
      (read-json (open-input-string gist-json)))

    ;; In this example, we want to map the JSON data
    ;; into a `gist' struct.

    (struct gist (url
                  id
                  description
                  public
                  user
                  comments
                  comments-url
                  html-url
                  git-pull-url
                  git-push-url
                  created-at)
      #:transparent)

    ;; In addition to other data, the gist contains a
    ;; reference to a user.

    (struct user (login id avatar-url gravatar-id url)
      #:transparent)

    ;; Now, we describe how we want our jsexpr mapped
    ;; into out structures.

    (define gist-mapping
      (json-mapping
       (object gist
         [url : string]
         [id : string]
         [description : string]
         [public : bool]
         [user : user-mapping] ;; <- The gist contains a user
         [comments : number ]
         [comments_url : string]
         [html_url : string]
         [git_pull_url : string]
         [git_push_url : string]
         [created_at : string])))
    
    (define user-mapping
      (json-mapping
       (object user
         [login : string]
         [id : number]
         [avatar_url : string]
         [gravatar_id : string]
         [url : string])))
      
    ;; Transform the given jsexpr into a racket datum.
    (define the-gist
      (jsexpr->datum gist-mapping a-gist))

    ;; ... and transform it back into a jsexpr
    (define the-jsexpr
      (datum->jsexpr gist-mapping the-gist))

And that's all. There is still a lot of functionality missing, but
for simple mappings it is enough as it is.

Right now, `json-mapping` supports the following mappings:
 - `string`, a string,
 - `number`, an integer or inexact real,
 - `bool`, a boolean,
 - `list`, a list of mappings (e.g. `(list string)` or
   `(list (object [foo : number]))`)
 - `object`, a hash or Racket struct,
 - `literal`, a literal datum (e.g. `(literal "a")` matches only the `"a"`
    value and nothing more),
 - `or`, any of a given set of mappings (e.g. `(or string number)` matches
   either a string or a number).

`object` mappings match both literal hashes and struct mappings. When an
`object` mapping has the form
```racket
(object cons [a : m1] [b : m2] ...)
```
it is assumed that the jsexpr should be transformed into a struct with the given
`cons` constructor. If otherwise the `object`
mapping is like:
```racket
(object [a : m1] [b : m2] ...)
```
the jsexpr will be transformed into an immutable hash. For example:
```racket
(datum->jsexpr (json-mapping (object [foo : string]))
               (hash 'foo "a"))
=> '#hash((foo . "a"))

(struct bar (foo) #:transparent)

(jsexpr->datum (json-mapping (object bar [foo : string]))
               (hash 'foo "a"))
=> (bar "a")
```

Finally, there are a couple of restrictions you have to meet in order to use
this library:
  1. All structs must be transparent (`json-mapping` needs to use
    `struct->vector` internally),
  2. An object mapping must declare its components in the order expected by
     the constructor function.