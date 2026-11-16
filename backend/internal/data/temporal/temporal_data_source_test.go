package temporal

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	enumspb "go.temporal.io/api/enums/v1"
	namespacepb "go.temporal.io/api/namespace/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/mocks"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/types/known/durationpb"
)

type namespaceReader struct {
	workflowservice.WorkflowServiceClient
	response *workflowservice.DescribeNamespaceResponse
	err      error
	names    []string
}

func (reader *namespaceReader) DescribeNamespace(_ context.Context, request *workflowservice.DescribeNamespaceRequest, _ ...grpc.CallOption) (*workflowservice.DescribeNamespaceResponse, error) {
	reader.names = append(reader.names, request.Namespace)
	return reader.response, reader.err
}

func TestReadinessRequiresHistoryForTheWholeOutboxDeliveryWindow(t *testing.T) {
	for _, scenario := range []struct {
		name      string
		retention *durationpb.Duration
		wantReady bool
	}{
		{"missing retention", nil, false},
		{"too short", durationpb.New(24*time.Hour - time.Second), false},
		{"negative", durationpb.New(-time.Hour), false},
		{"invalid duration", &durationpb.Duration{Seconds: 86400, Nanos: 1000000000}, false},
		{"whole delivery window", durationpb.New(24 * time.Hour), true},
		{"managed namespace", durationpb.New(72 * time.Hour), true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			remote := mocks.NewClient(t)
			reader := &namespaceReader{response: &workflowservice.DescribeNamespaceResponse{
				NamespaceInfo: &namespacepb.NamespaceInfo{State: enumspb.NAMESPACE_STATE_REGISTERED},
				Config:        &namespacepb.NamespaceConfig{WorkflowExecutionRetentionTtl: scenario.retention},
			}}
			remote.On("CheckHealth", mock.Anything, mock.Anything).Return(&client.CheckHealthResponse{}, nil)
			remote.On("WorkflowService").Return(reader)
			source := &TemporalDataSource{connection: remote, namespace: "test-namespace"}
			if err := source.Ping(t.Context()); (err == nil) != scenario.wantReady {
				t.Fatalf("namespace readiness %v, want ready %v", err, scenario.wantReady)
			}
			if scenario.wantReady {
				reader.response.Config.WorkflowExecutionRetentionTtl = durationpb.New(time.Hour)
				if err := source.Ping(t.Context()); err == nil {
					t.Fatal("readiness ignored a shortened retention configuration")
				}
			}
		})
	}
}

func TestNamespaceRetentionGuardChecksFreshConfigurationWithoutHealthRPC(t *testing.T) {
	remote := mocks.NewClient(t)
	reader := &namespaceReader{response: &workflowservice.DescribeNamespaceResponse{
		NamespaceInfo: &namespacepb.NamespaceInfo{State: enumspb.NAMESPACE_STATE_REGISTERED},
		Config:        &namespacepb.NamespaceConfig{WorkflowExecutionRetentionTtl: durationpb.New(72 * time.Hour)},
	}}
	remote.On("WorkflowService").Return(reader).Twice()
	source := &TemporalDataSource{connection: remote, namespace: "admission-namespace"}
	if err := source.CheckNamespaceRetention(t.Context()); err != nil {
		t.Fatal(err)
	}
	reader.response.Config.WorkflowExecutionRetentionTtl = durationpb.New(time.Hour)
	if err := source.CheckNamespaceRetention(t.Context()); err == nil {
		t.Fatal("admission guard ignored shortened retention")
	}
	if len(reader.names) != 2 || reader.names[0] != source.namespace || reader.names[1] != source.namespace {
		t.Fatalf("namespace checks: %v", reader.names)
	}
	remote.AssertNotCalled(t, "CheckHealth", mock.Anything, mock.Anything)
}

func TestNamespaceRetentionGuardRejectsUnavailableOrInvalidNamespace(t *testing.T) {
	failure := errors.New("namespace unavailable")
	for _, scenario := range []struct {
		name     string
		response *workflowservice.DescribeNamespaceResponse
		err      error
	}{
		{name: "missing response"},
		{name: "missing namespace", response: &workflowservice.DescribeNamespaceResponse{}},
		{name: "deleted namespace", response: &workflowservice.DescribeNamespaceResponse{NamespaceInfo: &namespacepb.NamespaceInfo{State: enumspb.NAMESPACE_STATE_DELETED}}},
		{name: "missing retention", response: &workflowservice.DescribeNamespaceResponse{NamespaceInfo: &namespacepb.NamespaceInfo{State: enumspb.NAMESPACE_STATE_REGISTERED}}},
		{name: "invalid retention", response: &workflowservice.DescribeNamespaceResponse{
			NamespaceInfo: &namespacepb.NamespaceInfo{State: enumspb.NAMESPACE_STATE_REGISTERED},
			Config:        &namespacepb.NamespaceConfig{WorkflowExecutionRetentionTtl: &durationpb.Duration{Seconds: 86400, Nanos: 1000000000}},
		}},
		{name: "RPC error", err: failure},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			remote := mocks.NewClient(t)
			remote.On("WorkflowService").Return(&namespaceReader{response: scenario.response, err: scenario.err}).Once()
			source := &TemporalDataSource{connection: remote, namespace: "admission-namespace"}
			err := source.CheckNamespaceRetention(t.Context())
			if err == nil || scenario.err != nil && !errors.Is(err, scenario.err) {
				t.Fatalf("namespace validation returned %v", err)
			}
			remote.AssertNotCalled(t, "CheckHealth", mock.Anything, mock.Anything)
		})
	}
}
