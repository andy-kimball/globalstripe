package main

import (
	"fmt"
	"log"
	"regexp"
	"runtime/debug"
)

type route struct {
	Path   string
	Method string
	Callback func(request Request, pathMatches ...string) Response

	regex *regexp.Regexp
}

type router []route

func (r router) Init() {
	for i := range r {
		r[i].regex = regexp.MustCompile(r[i].Path)
	}
}

func (r router) RouteRequest(request Request) (response Response) {
	defer func() {
		if e := recover(); e != nil {
			text := fmt.Sprintf("500 (Internal Server Error): %v\n%v\n", e, string(debug.Stack()))
			log.Printf(text)
			response = makeResponse(500, text)
		}
	}()

	for i := range r {
		if request.HTTPMethod != r[i].Method {
			continue
		}
		matches := r[i].regex.FindStringSubmatch(request.Path)
		if matches == nil || len(matches[0]) != len(request.Path) {
			continue
		}
		return r[i].Callback(request, matches[1:]...)
	}
	return notFoundResponse(fmt.Sprintf("%s %s", request.HTTPMethod, request.Path))
}
