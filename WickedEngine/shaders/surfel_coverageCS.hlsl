#include "globals.hlsli"
#include "ShaderInterop_Renderer.h"

#define SURFEL_NEIGHBOR_SAMPLING

//#define SURFEL_DEBUG_NORMAL
#define SURFEL_DEBUG_COLOR
//#define SURFEL_DEBUG_POINT
//#define SURFEL_DEBUG_RANDOM


static const uint nice_colors_size = 5;
static const float3 nice_colors[nice_colors_size] = {
	float3(0,0,1),
	float3(0,1,1),
	float3(0,1,0),
	float3(1,1,0),
	float3(1,0,0),
};
float3 hash_color(uint index)
{
	return nice_colors[index % nice_colors_size];
}


STRUCTUREDBUFFER(surfelBuffer, Surfel, TEXSLOT_ONDEMAND0);
RAWBUFFER(surfelStatsBuffer, TEXSLOT_ONDEMAND1);
STRUCTUREDBUFFER(surfelIndexBuffer, uint, TEXSLOT_ONDEMAND2);
STRUCTUREDBUFFER(surfelCellIndexBuffer, float, TEXSLOT_ONDEMAND3);
STRUCTUREDBUFFER(surfelCellOffsetBuffer, uint, TEXSLOT_ONDEMAND4);

RWTEXTURE2D(coverage, uint, 0);
RWTEXTURE2D(debugUAV, unorm float4, 1);

groupshared uint GroupMinSurfelCount;

[numthreads(16, 16, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint groupIndex : SV_GroupIndex, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
	if (groupIndex == 0)
	{
		GroupMinSurfelCount = ~0;
	}
	GroupMemoryBarrierWithGroupSync();

	const float depth = texture_depth[DTid.xy];

	float4 debug = 0;

	if (depth > 0)
	{
		const float2 uv = ((float2)DTid.xy + 0.5) * g_xFrame_InternalResolution_rcp;
		const float3 P = reconstructPosition(uv, depth);

		const float4 g1 = texture_gbuffer1.SampleLevel(sampler_linear_clamp, uv, 0);
		const float3 N = normalize(g1.rgb * 2 - 1);

		uint surfel_count = surfelStatsBuffer.Load(SURFEL_STATS_OFFSET_COUNT);
		uint surfel_count_at_pixel = 0;

		int3 cell = surfel_cell(P);

#ifdef SURFEL_NEIGHBOR_SAMPLING
		// iterate through all [27] neighbor cells:
		[loop]
		for (int i = -1; i <= 1; ++i)
		{
			[loop]
			for (int j = -1; j <= 1; ++j)
			{
				[loop]
				for (int k = -1; k <= 1; ++k)
				{
					uint surfel_hash_target = surfel_hash(cell + int3(i, j, k));
#else
					uint surfel_hash_target = surfel_hash(cell);
#endif // SURFEL_NEIGHBOR_SAMPLING

					uint surfel_list_offset = surfelCellOffsetBuffer[surfel_hash_target];
					while (surfel_list_offset != ~0u && surfel_list_offset < surfel_count)
					{
						uint surfel_index = surfelIndexBuffer[surfel_list_offset];
						uint surfel_hash = surfelCellIndexBuffer[surfel_index];

						if (surfel_hash == surfel_hash_target)
						{
							Surfel surfel = surfelBuffer[surfel_index];
							float dist = length(P - surfel.position);
							if (dist <= SURFEL_RADIUS)
							{
								float3 normal = unpack_unitvector(surfel.normal);
								float dotN = dot(N, normal);
								if (dotN > 0)
								{
									surfel_count_at_pixel++;

									float contribution = 1;
									contribution *= saturate(1 - dist / SURFEL_RADIUS);
									contribution *= saturate(dotN);
									contribution = smoothstep(0, 1, contribution);
#ifdef SURFEL_DEBUG_NORMAL
									debug.rgb += normal * contribution;
									debug.a = 1;
#endif // SURFEL_DEBUG_NORMAL

#ifdef SURFEL_DEBUG_COLOR
									debug += float4(surfel.mean, 1) * contribution;
#endif // SURFEL_DEBUG_COLOR

#ifdef SURFEL_DEBUG_RANDOM
									debug += float4(hash_color(surfel_index), 1) * contribution;
#endif // SURFEL_DEBUG_RANDOM

								}

#ifdef SURFEL_DEBUG_POINT
								if (dist <= 0.05)
									debug = float4(1, 0, 0, 1);
#endif // SURFEL_DEBUG_POINT
							}
						}
						else
						{
							// in this case we stepped out of the surfel list of the cell
							break;
						}

						surfel_list_offset++;
					}

#ifdef SURFEL_NEIGHBOR_SAMPLING
				}
			}
		}
#endif // SURFEL_NEIGHBOR_SAMPLING

		surfel_count_at_pixel <<= 8;
		surfel_count_at_pixel |= (GTid.x & 0xF) << 4;
		surfel_count_at_pixel |= (GTid.y & 0xF) << 0;

		InterlockedMin(GroupMinSurfelCount, surfel_count_at_pixel);

#ifdef SURFEL_DEBUG_NORMAL
		debug.rgb = normalize(debug.rgb) * 0.5 + 0.5;
#endif // SURFEL_DEBUG_NORMAL

#if defined(SURFEL_DEBUG_COLOR) || defined(SURFEL_DEBUG_RANDOM)
		if (debug.a > 0)
		{
			debug /= debug.a;
		}
		else
		{
			debug = 0;
		}
#endif // SURFEL_DEBUG_COLOR || SURFEL_DEBUG_RANDOM
	}

	GroupMemoryBarrierWithGroupSync();

	if (groupIndex == 0)
	{
		coverage[Gid.xy] = GroupMinSurfelCount;
	}

	debugUAV[DTid.xy] = debug;
}
