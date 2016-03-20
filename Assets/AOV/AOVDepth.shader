Shader "Hidden/AOVDepth" {
SubShader {
	Tags { "RenderType"="Opaque" }
	Pass {
CGPROGRAM
#pragma vertex vert
#pragma fragment frag
#include "UnityCG.cginc"
struct v2f {
    float4 pos : SV_POSITION;
    float4 nz : TEXCOORD0;
};
v2f vert( appdata_base v ) {
    v2f o;
    o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
    o.nz.xyz = COMPUTE_VIEW_NORMAL;
    o.nz.w = COMPUTE_DEPTH_01;
    return o;
}
struct f2s {
	fixed depth : SV_Target0;
	fixed2 normal : SV_Target1;
};
f2s frag(v2f i) {
	f2s output;
	output.depth = i.nz.w;
	output.normal = EncodeViewNormalStereo (i.nz.xyz);
	return output;
}
ENDCG
	}
}
}
