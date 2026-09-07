import {View} from 'react-native'
import {Trans} from '@lingui/react/macro'

import {atoms as a, useTheme} from '#/alf'
import {Mark as Logo} from '#/components/icons/Logo'
import {Text} from '#/components/Typography'

const BUTTERFLY_SIZE = 80

/**
 * Empty-state shown in the leftover space beneath a post that has no replies.
 */
export function ThreadItemEmptyReplies({
  height,
  reservedBottom = 0,
}: {
  height: number
  reservedBottom?: number
}) {
  const t = useTheme()
  const muted = t.palette.contrast_300

  return (
    <View
      testID="threadEmptyReplies"
      style={[
        a.w_full,
        a.align_center,
        a.justify_center,
        a.px_lg,
        {
          height,
          paddingBottom: reservedBottom,
        },
      ]}>
      <Logo width={BUTTERFLY_SIZE} height={BUTTERFLY_SIZE} fill={muted} />
      <Text
        style={[
          a.text_sm,
          a.leading_snug,
          a.text_center,
          a.mt_md,
          {color: muted},
        ]}>
        <Trans>You can be first to comment</Trans>
      </Text>
    </View>
  )
}
