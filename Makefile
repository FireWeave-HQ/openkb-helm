.PHONY: test lint template package docker-build

test:
	./scripts/test.sh

lint:
	helm lint charts/openkb

template:
	helm template openkb charts/openkb --namespace openkb

package:
	helm package charts/openkb

docker-build:
	docker buildx build --load -f docker/Dockerfile -t openkb:0.5.0rc1 .
