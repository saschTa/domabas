package temporal

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/log"
)

type TemporalDataSource struct {
	connection client.Client
	namespace  string
}

func NewTemporalDataSource(ctx context.Context, address, namespace string, logger *slog.Logger) (*TemporalDataSource, error) {
	connection, err := client.DialContext(ctx, client.Options{
		HostPort: address, Namespace: namespace, Logger: log.NewStructuredLogger(logger),
	})
	if err != nil {
		return nil, fmt.Errorf("connect Temporal: %w", err)
	}
	source := &TemporalDataSource{connection: connection, namespace: namespace}
	if err := source.Ping(ctx); err != nil {
		source.Close()
		return nil, err
	}
	return source, nil
}

func (source *TemporalDataSource) Client() client.Client { return source.connection }

func (source *TemporalDataSource) Close() { source.connection.Close() }

func (source *TemporalDataSource) Ping(ctx context.Context) error {
	if _, err := source.connection.CheckHealth(ctx, &client.CheckHealthRequest{}); err != nil {
		return fmt.Errorf("Temporal health: %w", err)
	}
	namespace, err := source.connection.WorkflowService().DescribeNamespace(ctx, &workflowservice.DescribeNamespaceRequest{Namespace: source.namespace})
	if err != nil {
		return fmt.Errorf("Temporal namespace: %w", err)
	}
	if namespace.NamespaceInfo == nil || namespace.NamespaceInfo.State != enums.NAMESPACE_STATE_REGISTERED {
		return fmt.Errorf("Temporal namespace %q is not registered", source.namespace)
	}
	retention := namespace.GetConfig().GetWorkflowExecutionRetentionTtl()
	if retention == nil || retention.CheckValid() != nil || retention.AsDuration() < 24*time.Hour {
		return fmt.Errorf("Temporal namespace %q requires at least 24 hours of workflow history retention", source.namespace)
	}
	return nil
}
