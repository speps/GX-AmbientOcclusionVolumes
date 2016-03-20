Shader "Hidden/AOV"
{
	SubShader
	{
		Tags { "RenderType"="Opaque" }
		Pass
		{
			ZWrite Off
			Blend One One

			CGPROGRAM
				#pragma target 4.0
				#pragma vertex VS_Main
				#pragma geometry GS_Main
				#pragma fragment FS_Main
				#include "UnityCG.cginc"

				struct GS_INPUT
				{
					float4 Position : POSITION;
				};

				struct FS_INPUT
				{
					float4 Position : SV_POSITION;
					float4 ScreenUV : TEXCOORD0;
					float3 SourceVertex[3] : ATTRIBUTE0;
					float3 EdgeNormal[3] : NORMAL0;
					float3 TopNormal : NORMAL3;
					float Area : ATTRIBUTE3;
					float MeanCoverage : ATTRIBUTE4;
				};

				float AOV_maxObscuranceDistance;

				GS_INPUT VS_Main(appdata_base v)
				{
					GS_INPUT output = (GS_INPUT)0;
					output.Position =  mul(_Object2World, v.vertex);
					return output;
				}

				void Emit(inout TriangleStream<FS_INPUT> triStream, const in float4 position, const in GS_INPUT p[3],
					const in float3 edgeNormal[3], const in float3 topNormal, const in float area, const in float meanCoverage)
				{
					FS_INPUT vertex;
					vertex.Position = position;
					vertex.ScreenUV = ComputeScreenPos(position);
					vertex.SourceVertex[0] = p[0].Position.xyz;
					vertex.SourceVertex[1] = p[1].Position.xyz;
					vertex.SourceVertex[2] = p[2].Position.xyz;
					vertex.EdgeNormal = edgeNormal;
					vertex.TopNormal = topNormal;
					vertex.Area = area;
					vertex.MeanCoverage = meanCoverage;
					triStream.Append(vertex);
				}

				float3 getIntersection(float3 p1, float3 v1, float3 p2, float3 v2)
				{
					float3 dp = p2 - p1;
					float3 dv = cross(v1, v2);
					float a = dot(cross(dp, v2), dv) / dot(dv, dv);
					return p1 + a * v1;
				}

				[maxvertexcount(12)]
				void GS_Main(triangle GS_INPUT p[3], inout TriangleStream<FS_INPUT> triStream)
				{
					float3 negFaceNormal = cross(p[2].Position.xyz - p[0].Position.xyz, p[1].Position.xyz - p[0].Position.xyz);
					float sharedArea = length(negFaceNormal);
					negFaceNormal = normalize(negFaceNormal);

					float3 edge[3];
					float3 edgeNormal[3];
					{
						for (int i = 2, j = 0; j < 3; i = j++)
						{
							edge[i] = normalize(p[j].Position.xyz - p[i].Position.xyz);
							edgeNormal[i] = cross(edge[i], negFaceNormal);
						}
					}

					// bias is used to force low mip level, which gives a useful average across the triangle.
					//const float bias = 4.0f;
					//float4 LC = texture2D(lambertianCoverageMap, (texCoord[0] + texCoord[1] + texCoord[2]) / 3.0, bias) * lambertianCoverageConstant;
					//float sharedMeanCoverage = LC.a;
					float sharedMeanCoverage = 1.0f;

					// A triangular prism can be created as a single triangle strip containing 12 vertices and 10 triangles,
					// two of which are degenerate, or as two triangle strips containing 12 vertices and 8 triangles total.
					// We use the second method.
					//
					// Input vertices:
					//                            2
					//                         __*
					//                   ___--- /
					//             ___---      / 
					//            *-----------* 
					//           0            1
					//
					// Output vertices:
					//                             2, 6
					//                         __*
					//                   ___--- /|
					//             ___---  1,10/ |
					//       0, 8 *-----------*__* 4, 7
					//            |      ___--| /
					//            |___---     |/
					//            *-----------*
					//          5, 9           3, 11
					//
					// Output strips:
					//
					//                   2     4
					//                   *-----*              6   8  10   
					//                 / |\    | \             *--*--*
					//               /   | \   |   \           | /| /|
					//           0 *     |  \  |    * 5        |/ |/ |
					//               \   |   \ |   /           *--*--*
					//                 \ |    \| /            7   9  11
					//                   *-----*
					//                   1     3
					//

					// Coordinates of the volume vertices, after projection
					float4 v[6];

					// Largest possible extrusion
					float maxLen = AOV_maxObscuranceDistance * 2.0f;

					// Tracks whether the camera is inside the occlusion volume.  This is an incremental point-in-polyhedron test.
					// If any one plane returns false, inside will become false.  We begin by testing the top and bottom planes.
					float d = dot(p[0].Position.xyz - _WorldSpaceCameraPos, negFaceNormal);
					bool inside =
						(d > 0.0f) && // Plane of the triangle, bottom of the prism
						(d < AOV_maxObscuranceDistance);  // Plane of the top of the prism

					float maxLen2 = maxLen * maxLen;
					for (int i = 2, j = 0; j < 3; i = j++)
					{
						// Extend base vertex outwards
						float3 pi = p[j].Position.xyz - edgeNormal[i] * AOV_maxObscuranceDistance;
						float3 pj = p[j].Position.xyz - edgeNormal[j] * AOV_maxObscuranceDistance;

						// Find intersection between 2 edges
						float3 pt = getIntersection(pi, edge[i], pj, edge[j]);
						v[j].xyz = pt;

						// Test the plane through this face
						inside = inside && (dot(v[j].xyz - _WorldSpaceCameraPos, edgeNormal[j]) < 0.0f);

						// Extend upwards and project
						v[j + 3] = mul(UNITY_MATRIX_VP, float4(negFaceNormal * -AOV_maxObscuranceDistance + v[j].xyz, 1.0f));

						// Project the lower vertex as well
						v[j] = mul(UNITY_MATRIX_VP, float4(v[j].xyz, 1.0f));
					}

					if (inside)
					{
						// Emit full-screen quad
						//    
						//   0 *--* 2
						//     | /|
						//     |/ |
						//   1 *--* 3

						// In OpenGL, the screen has normalized (-1,-1) to (1,1) coordinates
						Emit(triStream, float4(-1.0f, -1.0f, 0.0f, 1.0f), p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
						Emit(triStream, float4(-1.0f,  1.0f, 0.0f, 1.0f), p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
						Emit(triStream, float4( 1.0f, -1.0f, 0.0f, 1.0f), p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
						Emit(triStream, float4( 1.0f,  1.0f, 0.0f, 1.0f), p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
					}
					else
					{
						// Emit a triangular prism

						// First strip
						{
							// Top triangle
							Emit(triStream, v[3], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
							Emit(triStream, v[4], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
							Emit(triStream, v[5], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);

							// Right side quad
							Emit(triStream, v[1], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
							Emit(triStream, v[2], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);

							// Bottom triangle
							Emit(triStream, v[0], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
						}
						triStream.RestartStrip();

						// Second strip
						{
							// Back-left quad
							Emit(triStream, v[5], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
							Emit(triStream, v[2], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
							Emit(triStream, v[3], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
							Emit(triStream, v[0], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);

							// Front quad
							Emit(triStream, v[4], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
							Emit(triStream, v[1], p, edgeNormal, negFaceNormal, sharedArea, sharedMeanCoverage);
						}
					}
					triStream.RestartStrip();
				}

				float AOV_falloffExponent;

				// No normalize or shared products
				float projArea(const in float3 a, const in float3 b, const in float3 n) {
					// 37.2 ms (without normalization in the projHemi method)

					// Note 1/sqrt and 1/length should both be optimize rsqrt
					float3 bXa = cross(b, a);
					float cosine = dot(a, b);
					float theta = acos(cosine * rsqrt(dot(a, a) * dot(b, b)));
					return theta * dot(n, bXa) * rsqrt(dot(bXa, bXa));
				}

				const float epsilon = 0.00001f;

				/**
				 Clips a triangle in \a v[0..2] to the plane through the origin with normal \a n
				 (and projects it onto the hemisphere if preprocessor macro NORMALIZE is #defined.) 

				 The result is a convex polygon in \a v[0..3]; the last vertex may be degenerate
				 and equal to the first vertex.  If that is the case, the function returns false.
				 The reason that the result is *always* returned in four vertices is that subsequent
				 algorithms typically iterate over edges, and the quad and tri case can be handled
				 without a branch for the first three edges under this ordering.

				 \return true if the result is a triangle, false if it is a quad

				 Optimized (by trial and error) for GeForce 280 under GLSL 1.50

				 Optimization intuition:
				 1. we want to maximize coherence (to keep all threads in a warp active) by quickly reducing to a small set of common cases,
				 2. minimize peak register count (to enable a large number of simultaneous threads), and
				 3. avoid non-constant array indexing (which expands to a huge set of branches on most GPUs)
				*/
				bool clipToPlane(const in float3 n, inout float3 v0, inout float3 v1, inout float3 v2, out float3 v3) {

					// Distances to the plane (this is an array parallel to v[], stored as a float3)
					float3 dist = float3(dot(v0, n), dot(v1, n), dot(v2, n));

					bool quad = false;

					// Perform this test conservatively since we want to eliminate
					// faces that are adjacent but below the point being shaded.
					// In order to be sure that two-sided surfaces don't slip and completly
					// occlude each other, we need a fairly large epsilon.  The same constant
					// appears in the ray tracer.

					if (!any(dist >= float(0.01f).xxx)) {
						// All clipped; no occlusion from this triangle
						discard;
					} else if (all(dist >= float(-epsilon).xxx)) {
						// None clipped (original triangle vertices are unmodified)
					} else {
						bool3 above = dist >= float(0.0).xxx;

						// There are either 1 or 2 vertices above the clipping plane.
						bool nextIsAbove;

						// Find the ccw-most vertex above the plane by cycling
						// the vertices in place.  There are three cases.
						if (above[1] && ! above[0]) {
							nextIsAbove = above[2];
							// Cycle once CCW.  Use v[3] as a temp
							v3 = v0; v0 = v1; v1 = v2; v2 = v3;
							dist = dist.yzx;
						} else if (above[2] && ! above[1]) {
							// Cycle once CW.  Use v3 as a temp.
							nextIsAbove = above[0];
							v3 = v2; v2 = v1; v1 = v0; v0 = v3;
							dist = dist.zxy;
						} else {
							nextIsAbove = above[1];
						}
						// Note: The above[] values are no longer in sync with v[] and dist[].

						// Both of the following branches require the same value, so we compute
						// it into v[3] and move it to v[2] if that was the required location.
						// This helps keep some more threads coherent.

						// Compute vertex 3 first so that we don't smash the data
						// we need to reuse in vertex 2 if this is a quad.
						v3 = lerp(v0, v2, dist[0] / (dist[0] - dist[2]));

						if (nextIsAbove) {
							// There is a quad above the plane
							quad = true;

							//    i0---------i1
							//      \        |
							//   .....B......A...
							//          \    |
							//            \  |
							//              i2
							v2 = lerp(v1, v2, dist[1] / (dist[1] - dist[2]));

						} else {
							// There is a triangle above the plane

							//            i0
							//           / |
							//         /   |
							//   .....B....A...
							//      /      |
							//    i2-------i1

							v2 = v3;
							v1 = lerp(v0, v1, dist[0] / (dist[0] - dist[1]));
						}
					}

					// For triangle output, duplicate first vertex to avoid a branch
					// (and therefore, incoherence) later
					v3 = quad ? v3 : v0;

					return quad;
				}

				float computeFalloffWeight(const in FS_INPUT input, in  float3 origin, out float3 p0, out float3 p1, out float3 p2)
				{
					// Let pm[i] = p[i].dot(m[i]),
					// where p[i] is the polygon's vertex in tangent space
					// and m[i] is the normal to edge i.  
					//
					// pm[3] uses p[0] and m[3], which is the negative
					// normal to the entire occluding polygon.  That is,
					// pm[3] is the distance to the occluding polygon.
					float4 pm;
					p0  = input.SourceVertex[0] - origin;

					// Always the top
					pm[3] = dot(p0, input.TopNormal);

					// Two early-out tests.
					//
					// Corectness: If distanceToPlane < 0, we're *behind* the entire volume.  We need to add a small offset
					// to ensure that we don't discard corners where a surface point is exactly
					// in the plane of the source triangle and might round off to "behind" it.
					//
					// Optimization: If area / distanceToPlane < smallConstant, then this is a small triangle relative to 
					// the point, so it will produce minimal occlusion that will round off to zero at the 
					// alpha blender.  Making the constant larger will start to abruptly truncate some occlusion.
					// Making the constant smaller will increase precision; the test can be eliminated entirely without
					// affecting correctness.
					if ((pm[3] < epsilon) || (input.Area < pm[3] * 0.3f)) {
						discard;
					}

					pm[0] = dot(p0, input.EdgeNormal[0]);

					p1  = input.SourceVertex[1] - origin;
					pm[1] = dot(p1, input.EdgeNormal[1]);

					p2  = input.SourceVertex[2] - origin;
					pm[2] = dot(p2, input.EdgeNormal[2]);

					// Let g[i] = max(0.0f, min(1.0f, 1.0f - pm[i] * invDelta));
					float4 g = clamp(float(1.0f).xxxx - pm / AOV_maxObscuranceDistance, float(0.0f).xxxx, float(1.0f).xxxx);

					g[3] = pow(g[3], AOV_falloffExponent);

					// Recall that meanCoverage is the average alpha value of the occluding polygon.
					float f = g[0] * g[1] * g[2] * g[3] * input.MeanCoverage;

					// If falloffWeight is low, there's no point in computing AO
					if (f < 0.1f) {
						discard;
					}

					return f;
				}


				/** Computes the form factor of polygon \a p[0..2] and a point at the origin with normal \a n.
					The result is on the scale 0..1.  DISCARDs if the form factor is zero. */
				float computeFormFactor(in float3 n, in float3 p0, in float3 p1, in float3 p2) {
					float3 p3;

					// Clip to the plane of the deferred shading pixel.  If the triangle
					// is entirely clipped, the function will DISCARD.

					// Will discard on zero area
					bool quad = clipToPlane(n, p0, p1, p2, p3);

					float result = 0.0f;
					if (quad) {
						result += projArea(p3, p0, n);
					}

					result += projArea(p0, p1, n);
					result += projArea(p1, p2, n);
					result += projArea(p2, p3, n);

					// Constants factored out of projArea
					const float adjust = 1.0f / (2.0f * 3.1415927f);
					return result * adjust;
				}

				float4x4 AOV_inverseView;
				sampler2D_float AOV_depthTexture;
				sampler2D AOV_normalsTexture;

				void getWorldPositionAndNormal(float2 screenUV, out float3 worldPosition, out float3 worldNormal)
				{
					float depth = tex2D(AOV_depthTexture, screenUV);
					float3 normal = DecodeViewNormalStereo(tex2D(AOV_normalsTexture, screenUV));

					float2 p11_22 = float2(unity_CameraProjection._11, unity_CameraProjection._22);
					float3 vpos = float3((screenUV * 2 - 1) / p11_22, -1) * depth * _ProjectionParams.z;
					worldPosition = mul((float3x3)AOV_inverseView, vpos) + _WorldSpaceCameraPos;
					worldNormal = mul((float3x3)AOV_inverseView, normal);
				}

				float4 FS_Main(FS_INPUT input) : COLOR
				{
					float2 screenUV = input.ScreenUV.xy / input.ScreenUV.w;
					float3 x, n;
					getWorldPositionAndNormal(screenUV, x, n);

					// Occluding triangle's vertices relative to the origin.
					float3 p0, p1, p2;

					// Compute falloff weight first because it will DISCARD if zero
					float falloffWeight = computeFalloffWeight(input, x, p0, p1, p2);

					// Cosine-weighted projected area
					float formFactor = computeFormFactor(n, p0, p1, p2);

					formFactor = saturate(formFactor * falloffWeight);

					return float4(formFactor.xxx, 1);
					//return float4(screenUV, 0, 1);
					//return float4(frac(x), 1);
				}

			ENDCG
		}
	}
	Fallback Off
}
