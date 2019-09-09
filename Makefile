.PHONY: build clean deploy

build:
	env GOOS=linux go build -ldflags="-s -w" -o bin/globalstripe main.go

clean:
	rm -rf ./bin

deploy: clean build
	sls deploy --verbose --region us-east-2
	sls deploy --verbose --region eu-west-3
	sls deploy --verbose --region ap-northeast-2
