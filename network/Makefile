
all: up

up:
	@#./byfn.sh up -a
	@./byfn.sh up -a -o etcdraft

down:
	@./byfn.sh down

config:
	@./byfn.sh generate

cc:
	@./byfn.sh deployCC -e sz_mycc1

.PHONY: clean
clean:
	@echo "every thing is clean up, no worry"
