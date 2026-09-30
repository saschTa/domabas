package temporal

import (
	"context"
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
}

func (reader *namespaceReader) DescribeNamespace(context.Context, *workflowservice.DescribeNamespaceRequest, ...grpc.CallOption) (*workflowservice.DescribeNamespaceResponse, error) {
	return reader.response, nil
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
