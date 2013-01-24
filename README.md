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
moderate ammount of boilerplate.

    (require json)

    (define jsexpr
      (read-json (open-input-string gist-json)))

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
    
    (struct user (login id avatar-url gravatar-id url)
      #:transparent)

    (define the-gist
      (gist (hash-ref jsexpr 'url)
            (hash-ref jsexpr 'id)
	    (hash-ref jsexpr 'public)
	    ...))

This package tries to minimize the amount of code you have to write to
map between jsexprs and regular Racket structs.

    (require json-mapping)
    
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
      
    ;; Transform the given jsexpr into the Racket
    ;; datum specified by the mapping.
    (define the-gist
      (jsexpr->datum gist-mapping a-gist))

    ;; Transform the struct back into a jsexpr.
    (define the-jsexpr
      (datum->jsexpr gist-mapping the-gist))

And that's all.