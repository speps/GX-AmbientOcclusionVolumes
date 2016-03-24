Shader "AOV/RestoreDepth"
{
	SubShader
	{
		Cull Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert(appdata_base v)
			{
				v2f o;
				o.vertex = mul(UNITY_MATRIX_MVP, v.vertex);
				o.uv = v.texcoord;
				return o;
			}

			sampler2D _CameraDepthTexture;

			struct f2s
			{
				fixed4 Color : SV_Target;
				float Depth : SV_Depth;
			};

			f2s frag(v2f i)
			{
				f2s output = (f2s)0;
				output.Color = float4(0, 0, 0, 0);
				output.Depth = tex2D(_CameraDepthTexture, i.uv);
				return output;
			}
			ENDCG
		}
	}
}
