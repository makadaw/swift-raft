# Based on Swift gRPC Makefile
# Which Swift to use.
SWIFT:=swift
# Where products will be built; this is the SPM default.
SWIFT_BUILD_PATH:=./.build
SWIFT_BUILD_CONFIGURATION=debug
SWIFT_FLAGS=--build-path=${SWIFT_BUILD_PATH} --configuration=${SWIFT_BUILD_CONFIGURATION} --enable-test-discovery
# Force release configuration (for plugins)
SWIFT_FLAGS_RELEASE=$(patsubst --configuration=%,--configuration=release,$(SWIFT_FLAGS))

# protoc plugins.
PROTOC_GEN_SWIFT=${SWIFT_BUILD_PATH}/release/protoc-gen-swift
PROTOC_GEN_GRPC_SWIFT=${SWIFT_BUILD_PATH}/release/protoc-gen-grpc-swift

SWIFT_BUILD:=${SWIFT} build ${SWIFT_FLAGS}
SWIFT_BUILD_RELEASE:=${SWIFT} build ${SWIFT_FLAGS_RELEASE}
SWIFT_TEST:=${SWIFT} test ${SWIFT_FLAGS}
SWIFT_PACKAGE:=${SWIFT} package ${SWIFT_FLAGS}

### Package and plugin build targets ###########################################

all:
	${SWIFT_BUILD}

Package.resolved:
	${SWIFT_PACKAGE} resolve

${PROTOC_GEN_GRPC_SWIFT}: Package.resolved
	${SWIFT_BUILD_RELEASE} --product protoc-gen-grpc-swift
	${SWIFT_BUILD_RELEASE} --product protoc-gen-swift


### Protobuf Generation ########################################################

%.pb.swift: %.proto ${PROTOC_GEN_SWIFT}
	protoc $< \
		--proto_path=$(dir $<) \
		--experimental_allow_proto3_optional \
		--plugin=${PROTOC_GEN_SWIFT} \
		--swift_opt=Visibility=Internal \
		--swift_out=$(dir $<)

%.grpc.swift: %.proto ${PROTOC_GEN_GRPC_SWIFT}
	protoc $< \
		--proto_path=$(dir $<) \
		--experimental_allow_proto3_optional \
		--plugin=${PROTOC_GEN_GRPC_SWIFT} \
		--grpc-swift_opt=Visibility=Internal \
		--grpc-swift_out=$(dir $<)

# Generates protobufs and gRPC for Raft
RAFT_PROTO=Sources/Raft/Proto/raft.proto
RAFT_PB=$(RAFT_PROTO:.proto=.pb.swift)
RAFT_GRPC=$(RAFT_PROTO:.proto=.grpc.swift)

# Example app protocol
APP_PROTO=Sources/LocalCluster/Proto/example.proto
APP_PB=$(APP_PROTO:.proto=.pb.swift)

.PHONY:
generate: ${PROTOC_GEN_GRPC_SWIFT} ${RAFT_PB} ${RAFT_GRPC} ${APP_PB}

swiftlint: 
	${SWIFT} run swiftlint lint --strict --config .swiftlint.yml

### Testing ####################################################################

# Normal test suite.
.PHONY:
test:
	${SWIFT_TEST}

# Normal test suite with TSAN enabled.
.PHONY:
test-tsan:
	${SWIFT_TEST} --sanitize=thread

.PHONY:
LocalCluster:
	${SWIFT_BUILD}
	${SWIFT_BUILD_PATH}/debug/LocalCluster

### Misc. ######################################################################

.PHONY:
clean:
	-rm -rf ${SWIFT_BUILD_PATH}
