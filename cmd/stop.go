// Copyright 2020 PingCAP, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// See the License for the specific language governing permissions and
// limitations under the License.

package cmd

import (
	"github.com/pingcap-incubator/tiops/pkg/logger"
	"github.com/pingcap-incubator/tiops/pkg/meta"
	operator "github.com/pingcap-incubator/tiops/pkg/operation"
	"github.com/pingcap-incubator/tiops/pkg/task"
	"github.com/pingcap-incubator/tiup/pkg/utils"
	"github.com/pingcap/errors"
	"github.com/spf13/cobra"
)

func newStopCmd() *cobra.Command {
	var options operator.Options
	cmd := &cobra.Command{
		Use:   "stop <cluster-name>",
		Short: "Stop a TiDB cluster",
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) != 1 {
				return cmd.Help()
			}

			clusterName := args[0]
			if utils.IsNotExist(meta.ClusterPath(clusterName, meta.MetaFileName)) {
				return errors.Errorf("cannot stop non-exists cluster %s", clusterName)
			}

			logger.EnableAuditLog()
			metadata, err := meta.ClusterMetadata(clusterName)
			if err != nil {
				return err
			}

			t := task.NewBuilder().
				SSHKeySet(
					meta.ClusterPath(clusterName, "ssh", "id_rsa"),
					meta.ClusterPath(clusterName, "ssh", "id_rsa.pub")).
				ClusterSSH(metadata.Topology, metadata.User).
				ClusterOperate(metadata.Topology, operator.StopOperation, options).
				Build()

			return t.Execute(task.NewContext())

		},
	}

	cmd.Flags().StringSliceVarP(&options.Roles, "role", "R", nil, "Only stop specified roles")
	cmd.Flags().StringSliceVarP(&options.Nodes, "node", "N", nil, "Only stop specified nodes")
	return cmd
}
