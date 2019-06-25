﻿// Copyright (c) Microsoft Corporation.  All Rights Reserved.  Licensed under the MIT License.  See License in the project root for license information.

namespace Microsoft.Graph.GraphODataPowerShellSDKWriter.Generator.Behaviors
{
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using Microsoft.Graph.GraphODataPowerShellSDKWriter.Generator.Models;
    using Microsoft.Graph.GraphODataPowerShellSDKWriter.Utils;
    using Vipr.Core.CodeModel;

    public static class OdcmModelToNodesConversionBehavior
    {
        /// <summary>
        /// The maximum depth to which we should traverse the ODCM model.
        /// This is primarily to ensure that we don't generate cmdlets for an unreasonable number of routes.
        /// </summary>
        private const int MaxTraversalDepth = 5;

        /// <summary>
        /// Converts the structure of an ODCM model into a tree and returns all of the nodes in the tree.
        /// The first node returned is guaranteed to be the root of the tree, however the order of the remaining nodes is undetermined.
        /// </summary>
        /// <param name="obj">The ODCM model to convert</param>
        /// <returns>The root node of the created tree.</returns>
        public static IEnumerable<OdcmNode> ConvertToOdcmNodes(this OdcmModel model)
        {
            if (model == null)
            {
                throw new ArgumentNullException(nameof(model));
            }

            // Create a stack to allow us to traverse the model
            Stack<OdcmNode> unvisited = new Stack<OdcmNode>();

            // The EntityContainer in the model represents all of the data exposed through the OData service
            OdcmClass entityContainer = model.EntityContainer;

            // Evaluate the EntityContainer's children
            foreach (OdcmProperty prop in entityContainer.GetChildObjects(model))
            {
                // Mark the EntityContainer's properties as "to be expanded" if it is not a "$ref" property
                unvisited.Push(new OdcmNode(prop));
            }

            // Continue adding to the tree until there are no more nodes to expand
            while (unvisited.Any())
            {
                // Get the next node to expand
                OdcmNode currentNode = unvisited.Pop();

                // Return the visited node so it can be processed immediately
                yield return currentNode;

                // Mark the child nodes as "to be expanded" if we haven't hit the maximum traversal depth and it is not a reference property
                int currentDepth = new ODataRoute(currentNode).Segments.Count;
                if (currentDepth <= MaxTraversalDepth && !currentNode.OdcmProperty.IsReference(currentNode.Parent?.OdcmProperty))
                {
                    // Expand the node
                    IEnumerable<OdcmNode> childNodes = currentNode.CreateChildNodes(model);

                    // Mark the child nodes as "to be expanded"
                    foreach (OdcmNode childNode in childNodes)
                    {
                        unvisited.Push(childNode);
                    }
                }
            }
        }

        /// <summary>
        /// Expands a node into child nodes.
        /// </summary>
        /// <param name="node">The node to expand</param>
        /// <param name="model">The ODCM model</param>
        /// <returns>The child nodes if the node can be expanded, otherwise an empty list.</returns>
        private static IEnumerable<OdcmNode> CreateChildNodes(this OdcmNode node, OdcmModel model)
        {
            if (node == null)
            {
                throw new ArgumentNullException(nameof(node));
            }
            if (model == null)
            {
                throw new ArgumentNullException(nameof(model));
            }

            // Identify the kind of ODCM element this node represents and expand it if we need to
            OdcmProperty obj = node.OdcmProperty;
            IEnumerable<OdcmProperty> childObjects = obj.Type.GetChildObjects(model);

            // Don't allow loops in the list of ODCM nodes
            ICollection<string> parents = new HashSet<string>();
            OdcmNode currentNode = node;
            while (currentNode != null)
            {
                parents.Add(currentNode.OdcmProperty.CanonicalName());
                currentNode = currentNode.Parent;
            }

            return childObjects
                // Filter out the children we've already seen so we can avoid loops
                .Where(child => !parents.Contains(child.CanonicalName()))
                // Add the child nodes to the current node
                .Select(child => node.CreateChildNode(child));
        }

        /// <summary>
        /// Gets child expandable ODCM objects for an ODCM class.
        /// </summary>
        /// <param name="class">The ODCM class</param>
        /// <param name="model">The ODCM model</param>
        /// <returns>The child ODCM objects for the given ODCM class.</returns>
        private static IEnumerable<OdcmProperty> GetChildObjects(this OdcmType type, OdcmModel model)
        {
            if (type == null)
            {
                throw new ArgumentNullException(nameof(type));
            }
            if (model == null)
            {
                throw new ArgumentNullException(nameof(model));
            }

            // Get the property's type and subtypes, and expand them to get their properties
            IEnumerable<OdcmProperty> properties = type.EvaluateProperties().Where(prop => prop.IsODataRouteSegment(prop.Class == model.EntityContainer));
            IEnumerable<OdcmProperty> derivedTypeProperties = type.EvaluatePropertiesOnDerivedTypes().Where(prop => prop.IsODataRouteSegment(prop.Class == model.EntityContainer));

            return properties.Concat(derivedTypeProperties).Distinct();
        }
    }
}
