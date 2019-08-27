.PHONY: build clean deploy

build:
	env GOOS=linux go build -ldflags="-s -w" -o bin/globalstripe *.go

clean:
	rm -rf ./bin

deploy: clean build
	sls deploy --region us-east-2 --verbose
	sls deploy --region eu-west-3 --verbose
	sls deploy --region ap-northeast-2 --verbose
